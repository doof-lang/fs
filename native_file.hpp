#pragma once
#include "native_file_platform.hpp"

namespace doof_fs {
// The Doof wrapper owns this shared handle; the final reference closes it.
// Instances have a single mutable cursor and must not be used concurrently.
class NativeFile {
public:
    using Bytes = std::shared_ptr<std::vector<uint8_t>>;
    static doof::Result<std::shared_ptr<NativeFile>, IoError> open(
        const std::string& path, FileMode mode, bool create, FileLock lock, bool wait) {
        if ((path.empty() || path.find('\0') != std::string::npos)) return doof::Failure<IoError>{IoError::InvalidPath};
        bool writable = mode == FileMode::ReadWrite;
        if ((!writable && (create || lock == FileLock::Exclusive)))
            return doof::Failure<IoError>{IoError::InvalidArgument};
        int fd = file_platform::open(path, writable, create);
        if (fd < 0) return file_platform::failure<std::shared_ptr<NativeFile>>(errno);
        auto file = std::shared_ptr<NativeFile>(new NativeFile(fd, writable && lock != FileLock::Shared));
        auto info = file_platform::length(fd);
        if (doof::is_failure(info)) return doof::Failure<IoError>{doof::failure_error(info)};
        if (lock != FileLock::None) {
            auto result = file_platform::lock(fd, lock == FileLock::Exclusive, wait);
            if (doof::is_failure(result)) return doof::Failure<IoError>{doof::failure_error(result)};
        }
        return doof::Success<std::shared_ptr<NativeFile>>{file};
    }
    ~NativeFile() { if (fd_ >= 0) file_platform::close(fd_); }
    NativeFile(const NativeFile&) = delete;
    NativeFile& operator=(const NativeFile&) = delete;

    doof::Result<void, IoError> close() {
        if (fd_ < 0) return doof::Success<void>{};
        int fd = fd_; fd_ = -1;
        // Never retry close: a failing POSIX close may already release the fd.
        if (file_platform::close(fd) != 0) return file_platform::failure<void>(errno);
        return doof::Success<void>{};
    }
    doof::Result<int64_t, IoError> getPosition() {
        if (fd_ < 0) return doof::Failure<IoError>{IoError::Closed};
        auto position = file_platform::seek(fd_, 0, SEEK_CUR);
        if (position < 0) return file_platform::failure<int64_t>(errno);
        return doof::Success<int64_t>{position};
    }
    doof::Result<void, IoError> setPosition(int64_t position) {
        if (fd_ < 0) return doof::Failure<IoError>{IoError::Closed};
        if (position < 0) return doof::Failure<IoError>{IoError::InvalidArgument};
        if (file_platform::seek(fd_, position, SEEK_SET) < 0) return file_platform::failure<void>(errno);
        return doof::Success<void>{};
    }
    doof::Result<int64_t, IoError> length() {
        if (fd_ < 0) return doof::Failure<IoError>{IoError::Closed};
        return file_platform::length(fd_);
    }
    doof::Result<Bytes, IoError> readBytes(int64_t count, bool exact) {
        if (fd_ < 0) return doof::Failure<IoError>{IoError::Closed};
        if (count < 0) return doof::Failure<IoError>{IoError::InvalidArgument};
        auto data = std::make_shared<std::vector<uint8_t>>();
        // Grow incrementally rather than allocating an untrusted file length.
        while (count > 0) {
            auto size = data->size();
            size_t chunk = static_cast<size_t>(std::min<int64_t>(count, 65536));
            if (chunk > data->max_size() - size) return doof::Failure<IoError>{IoError::InvalidArgument};
            data->resize(size + chunk);
            auto n = file_platform::read(fd_, data->data() + size, chunk);
            if (n < 0) return file_platform::failure<Bytes>(errno);
            data->resize(size + static_cast<size_t>(n));
            if (n == 0) {
                if (exact) return doof::Failure<IoError>{IoError::UnexpectedEof};
                break;
            }
            count -= n;
            if (!exact) break;
        }
        return doof::Success<Bytes>{data};
    }
    doof::Result<void, IoError> writeBytes(const Bytes& data) {
        auto status = checkWritable();
        if (doof::is_failure(status)) return status;
        auto position = getPosition();
        if (doof::is_failure(position)) return doof::Failure<IoError>{doof::failure_error(position)};
        if (data->size() > static_cast<uint64_t>(INT64_MAX - doof::success_value(position)))
            return doof::Failure<IoError>{IoError::InvalidArgument};
        size_t offset = 0;
        while (offset < data->size()) {
            auto n = file_platform::write(fd_, data->data() + offset, std::min<size_t>(data->size() - offset, 65536));
            if (n < 0) return file_platform::failure<void>(errno);
            if (n == 0) return doof::Failure<IoError>{IoError::Other};
            offset += static_cast<size_t>(n);
        }
        return doof::Success<void>{};
    }
    doof::Result<void, IoError> truncate(int64_t size) {
        auto status = checkWritable();
        if (doof::is_failure(status)) return status;
        if (size < 0) return doof::Failure<IoError>{IoError::InvalidArgument};
        // Preserve the cursor explicitly: Windows CRT resizing may seek.
        auto position = getPosition();
        if (doof::is_failure(position)) return doof::Failure<IoError>{doof::failure_error(position)};
        if (file_platform::truncate(fd_, size) != 0) return file_platform::failure<void>(errno);
        return setPosition(doof::success_value(position));
    }
    doof::Result<void, IoError> flush() {
        auto status = checkWritable();
        if (doof::is_failure(status)) return status;
        if (file_platform::flush(fd_) != 0) return file_platform::failure<void>(errno);
        return doof::Success<void>{};
    }
private:
    NativeFile(int fd, bool writable) : fd_(fd), writable_(writable) {}
    doof::Result<void, IoError> checkWritable() {
        if (fd_ < 0) return doof::Failure<IoError>{IoError::Closed};
        if (!writable_) return doof::Failure<IoError>{IoError::PermissionDenied};
        return doof::Success<void>{};
    }
    int fd_;
    bool writable_;
};
} // namespace doof_fs
