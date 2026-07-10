#pragma once

#include "doof_runtime.hpp"
#include "types.hpp"

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <memory>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace doof_fs {

inline bool isInvalidPath(const std::string& path) {
    return path.empty() || path.find('\0') != std::string::npos;
}

inline IoError mapErrno(int err) {
    switch (err) {
        case ENOENT:
            return IoError::NotFound;
        case EACCES:
        case EPERM:
            return IoError::PermissionDenied;
        case EEXIST:
            return IoError::AlreadyExists;
        case EISDIR:
            return IoError::IsDirectory;
        case ENOTDIR:
            return IoError::NotDirectory;
        case EINVAL:
        case ENAMETOOLONG:
        case ELOOP:
            return IoError::InvalidPath;
        case EINTR:
            return IoError::Interrupted;
        default:
            return IoError::Other;
    }
}

template <typename T>
inline doof::Result<T, IoError> failureResult(int err) {
    return doof::Failure<IoError>{mapErrno(err)};
}

inline doof::Result<void, IoError> failureVoid(int err) {
    return doof::Failure<IoError>{mapErrno(err)};
}

inline std::string joinPath(const std::string& dirPath, const std::string& entryName) {
    if (dirPath.empty() || dirPath.back() == '/') {
        return dirPath + entryName;
    }
    return dirPath + "/" + entryName;
}

inline std::string basename(const std::string& path) {
    size_t end = path.size();
    while (end > 1 && path[end - 1] == '/') {
        --end;
    }

    const size_t slash = path.rfind('/', end - 1);
    if (slash == std::string::npos) {
        return path.substr(0, end);
    }
    if (slash == 0 && end == 1) {
        return "/";
    }
    return path.substr(slash + 1, end - slash - 1);
}

inline EntryKind entryKindFromMode(mode_t mode) {
    if (S_ISREG(mode)) {
        return EntryKind::File;
    }
    if (S_ISDIR(mode)) {
        return EntryKind::Directory;
    }
    if (S_ISLNK(mode)) {
        return EntryKind::Symlink;
    }
    return EntryKind::Other;
}

inline int normalizeBlockSize(int blockSize) {
    return blockSize > 0 ? blockSize : 65536;
}

inline std::shared_ptr<Instant> instantFromStatTime(time_t seconds) {
    return Instant::ofEpochSeconds(static_cast<int64_t>(seconds));
}

inline doof::Result<int, IoError> openReadableFile(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    const int fd = ::open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return failureResult<int>(errno);
    }

    struct stat st {};
    if (::fstat(fd, &st) != 0) {
        const int err = errno;
        ::close(fd);
        return failureResult<int>(err);
    }
    if (S_ISDIR(st.st_mode)) {
        ::close(fd);
        return doof::Failure<IoError>{IoError::IsDirectory};
    }

    return doof::Success<int>{fd};
}

inline doof::Result<int, IoError> openWritableFile(const std::string& path, int flags) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    const int fd = ::open(path.c_str(), flags, 0666);
    if (fd < 0) {
        return failureResult<int>(errno);
    }

    return doof::Success<int>{fd};
}

inline doof::Result<void, IoError> writeAll(int fd, const uint8_t* data, size_t size);

[[noreturn]] inline void panicStreamReadFailure(const char* streamKind, int err) {
    doof::panic(
        std::string("fs ") + streamKind + " stream read failed: " + IoError_name(mapErrno(err)) +
        " (errno=" + std::to_string(err) + ": " + std::strerror(err) + ")"
    );
}

class NativeBlobReadStream {
public:
    static doof::Result<std::shared_ptr<NativeBlobReadStream>, IoError> open(const std::string& path, int32_t blockSize) {
        const auto opened = openReadableFile(path);
        if (doof::is_failure(opened)) {
            return doof::Failure<IoError>{doof::failure_error(opened)};
        }

        return doof::Success<std::shared_ptr<NativeBlobReadStream>>{std::shared_ptr<NativeBlobReadStream>(new NativeBlobReadStream(doof::success_value(opened), normalizeBlockSize(blockSize)))};
    }

    ~NativeBlobReadStream() {
        if (fd_ >= 0) {
            ::close(fd_);
        }
    }

    std::shared_ptr<std::vector<uint8_t>> next() {
        if (done_) {
            return nullptr;
        }

        auto chunk = std::make_shared<std::vector<uint8_t>>(static_cast<size_t>(blockSize_));
        while (true) {
            const ssize_t readCount = ::read(fd_, chunk->data(), chunk->size());
            if (readCount < 0) {
                if (errno == EINTR) {
                    continue;
                }
                const int err = errno;
                done_ = true;
                ::close(fd_);
                fd_ = -1;
                panicStreamReadFailure("blob", err);
            }
            if (readCount == 0) {
                done_ = true;
                ::close(fd_);
                fd_ = -1;
                return nullptr;
            }

            chunk->resize(static_cast<size_t>(readCount));
            return chunk;
        }
    }

private:
    NativeBlobReadStream(int fd, int32_t blockSize)
        : fd_(fd), blockSize_(normalizeBlockSize(blockSize)), done_(false) {}

    int fd_;
    int32_t blockSize_;
    bool done_;
};

class NativeFileWriteStream {
public:
    static doof::Result<std::shared_ptr<NativeFileWriteStream>, IoError> open(const std::string& path) {
        const auto opened = openWritableFile(path, O_WRONLY | O_CREAT | O_TRUNC);
        if (doof::is_failure(opened)) {
            return doof::Failure<IoError>{doof::failure_error(opened)};
        }

        return doof::Success<std::shared_ptr<NativeFileWriteStream>>{std::shared_ptr<NativeFileWriteStream>(new NativeFileWriteStream(doof::success_value(opened)))};
    }

    ~NativeFileWriteStream() {
        if (fd_ >= 0) {
            ::close(fd_);
        }
    }

    doof::Result<void, IoError> writeBlob(const std::shared_ptr<std::vector<uint8_t>>& data) {
        const uint8_t* raw = nullptr;
        size_t size = 0;
        if (data) {
            raw = data->data();
            size = data->size();
        }

        return writeAll(fd_, raw, size);
    }

    doof::Result<void, IoError> writeLine(const std::string& line) {
        const auto lineResult = writeAll(fd_, reinterpret_cast<const uint8_t*>(line.data()), line.size());
        if (doof::is_failure(lineResult)) {
            return lineResult;
        }

        const uint8_t newline = '\n';
        return writeAll(fd_, &newline, 1);
    }

    doof::Result<void, IoError> close() {
        if (fd_ < 0) {
            return doof::Success<void>{};
        }

        const int fd = fd_;
        fd_ = -1;
        if (::close(fd) != 0) {
            return failureVoid(errno);
        }

        return doof::Success<void>{};
    }

private:
    explicit NativeFileWriteStream(int fd)
        : fd_(fd) {}

    int fd_;
};

inline doof::Result<std::shared_ptr<std::vector<uint8_t>>, IoError> readBlob(const std::string& path) {
    const auto opened = openReadableFile(path);
    if (doof::is_failure(opened)) {
        return doof::Failure<IoError>{doof::failure_error(opened)};
    }

    const int fd = doof::success_value(opened);

    auto data = std::make_shared<std::vector<uint8_t>>();
    uint8_t buffer[4096];
    while (true) {
        const ssize_t readCount = ::read(fd, buffer, sizeof(buffer));
        if (readCount < 0) {
            if (errno == EINTR) {
                continue;
            }
            const int err = errno;
            ::close(fd);
            return failureResult<std::shared_ptr<std::vector<uint8_t>>>(err);
        }
        if (readCount == 0) {
            break;
        }
        data->insert(data->end(), buffer, buffer + readCount);
    }

    ::close(fd);
    return doof::Success<std::shared_ptr<std::vector<uint8_t>>>{data};
}

inline doof::Result<std::string, IoError> readText(const std::string& path) {
    const auto raw = readBlob(path);
    if (doof::is_failure(raw)) {
        return doof::Failure<IoError>{doof::failure_error(raw)};
    }

    const auto& bytes = *doof::success_value(raw);
    return doof::Success<std::string>{std::string(bytes.begin(), bytes.end())};
}

inline doof::Result<void, IoError> writeAll(int fd, const uint8_t* data, size_t size) {
    size_t written = 0;
    while (written < size) {
        const ssize_t writeCount = ::write(fd, data + written, size - written);
        if (writeCount < 0) {
            if (errno == EINTR) {
                continue;
            }
            return failureVoid(errno);
        }
        written += static_cast<size_t>(writeCount);
    }
    return doof::Success<void>{};
}

inline doof::Result<void, IoError> writeText(const std::string& path, const std::string& content) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd < 0) {
        return failureVoid(errno);
    }

    const auto result = writeAll(fd, reinterpret_cast<const uint8_t*>(content.data()), content.size());
    const int closeResult = ::close(fd);
    if (doof::is_failure(result)) {
        return result;
    }
    if (closeResult != 0) {
        return failureVoid(errno);
    }
    return doof::Success<void>{};
}

inline doof::Result<void, IoError> writeBlob(
    const std::string& path,
    const std::shared_ptr<std::vector<uint8_t>>& data
) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd < 0) {
        return failureVoid(errno);
    }

    const uint8_t* raw = nullptr;
    size_t size = 0;
    if (data) {
        raw = data->data();
        size = data->size();
    }
    const auto result = writeAll(fd, raw, size);
    const int closeResult = ::close(fd);
    if (doof::is_failure(result)) {
        return result;
    }
    if (closeResult != 0) {
        return failureVoid(errno);
    }
    return doof::Success<void>{};
}

inline doof::Result<void, IoError> appendText(const std::string& path, const std::string& content) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) {
        return failureVoid(errno);
    }

    const auto result = writeAll(fd, reinterpret_cast<const uint8_t*>(content.data()), content.size());
    const int closeResult = ::close(fd);
    if (doof::is_failure(result)) {
        return result;
    }
    if (closeResult != 0) {
        return failureVoid(errno);
    }
    return doof::Success<void>{};
}

inline doof::Result<void, IoError> appendBlob(
    const std::string& path,
    const std::shared_ptr<std::vector<uint8_t>>& data
) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) {
        return failureVoid(errno);
    }

    const uint8_t* raw = nullptr;
    size_t size = 0;
    if (data) {
        raw = data->data();
        size = data->size();
    }
    const auto result = writeAll(fd, raw, size);
    const int closeResult = ::close(fd);
    if (doof::is_failure(result)) {
        return result;
    }
    if (closeResult != 0) {
        return failureVoid(errno);
    }
    return doof::Success<void>{};
}

inline bool exists(const std::string& path) {
    if (isInvalidPath(path)) {
        return false;
    }

    struct stat st {};
    return ::lstat(path.c_str(), &st) == 0;
}

inline bool isFile(const std::string& path) {
    if (isInvalidPath(path)) {
        return false;
    }

    struct stat st {};
    return ::lstat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

inline bool isDirectory(const std::string& path) {
    if (isInvalidPath(path)) {
        return false;
    }

    struct stat st {};
    return ::lstat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

inline doof::Result<std::shared_ptr<FileInfo>, IoError> metadata(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    struct stat st {};
    if (::lstat(path.c_str(), &st) != 0) {
        return failureResult<std::shared_ptr<FileInfo>>(errno);
    }

    const int64_t size = S_ISREG(st.st_mode) ? static_cast<int64_t>(st.st_size) : 0;
    return doof::Success<std::shared_ptr<FileInfo>>{std::make_shared<FileInfo>(
            basename(path),
            entryKindFromMode(st.st_mode),
            size,
            instantFromStatTime(st.st_mtime)
        )};
}

inline doof::Result<std::shared_ptr<std::vector<std::shared_ptr<FileInfo>>>, IoError> readDir(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    DIR* dir = ::opendir(path.c_str());
    if (!dir) {
        return failureResult<std::shared_ptr<std::vector<std::shared_ptr<FileInfo>>>>(errno);
    }

    auto entries = std::make_shared<std::vector<std::shared_ptr<FileInfo>>>();
    while (true) {
        errno = 0;
        dirent* rawEntry = ::readdir(dir);
        if (!rawEntry) {
            if (errno != 0) {
                const int err = errno;
                ::closedir(dir);
                return failureResult<std::shared_ptr<std::vector<std::shared_ptr<FileInfo>>>>(err);
            }
            break;
        }

        const std::string name(rawEntry->d_name);
        if (name == "." || name == "..") {
            continue;
        }

        const std::string fullPath = joinPath(path, name);
        struct stat st {};
        if (::lstat(fullPath.c_str(), &st) != 0) {
            const int err = errno;
            ::closedir(dir);
            return failureResult<std::shared_ptr<std::vector<std::shared_ptr<FileInfo>>>>(err);
        }

        const int64_t size = S_ISREG(st.st_mode) ? static_cast<int64_t>(st.st_size) : 0;
        entries->push_back(std::make_shared<FileInfo>(
            name,
            entryKindFromMode(st.st_mode),
            size,
            instantFromStatTime(st.st_mtime)
        ));
    }

    ::closedir(dir);
    return doof::Success<std::shared_ptr<std::vector<std::shared_ptr<FileInfo>>>>{entries};
}

inline doof::Result<void, IoError> mkdir(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }
    if (::mkdir(path.c_str(), 0777) != 0) {
        return failureVoid(errno);
    }
    return doof::Success<void>{};
}

inline doof::Result<void, IoError> remove(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    struct stat st {};
    if (::lstat(path.c_str(), &st) != 0) {
        return failureVoid(errno);
    }

    const int rc = S_ISDIR(st.st_mode) ? ::rmdir(path.c_str()) : ::unlink(path.c_str());
    if (rc != 0) {
        return failureVoid(errno);
    }
    return doof::Success<void>{};
}

inline doof::Result<void, IoError> rename(const std::string& sourcePath, const std::string& destPath) {
    if (isInvalidPath(sourcePath) || isInvalidPath(destPath)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }
    if (::rename(sourcePath.c_str(), destPath.c_str()) != 0) {
        return failureVoid(errno);
    }
    return doof::Success<void>{};
}

inline doof::Result<void, IoError> copy(const std::string& sourcePath, const std::string& destPath) {
    if (isInvalidPath(sourcePath) || isInvalidPath(destPath)) {
        return doof::Failure<IoError>{IoError::InvalidPath};
    }

    struct stat srcStat {};
    if (::stat(sourcePath.c_str(), &srcStat) != 0) {
        return failureVoid(errno);
    }
    if (S_ISDIR(srcStat.st_mode)) {
        return doof::Failure<IoError>{IoError::IsDirectory};
    }

    const int srcFd = ::open(sourcePath.c_str(), O_RDONLY);
    if (srcFd < 0) {
        return failureVoid(errno);
    }

    const int destFd = ::open(destPath.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_TRUNC, 0666);
    if (destFd < 0) {
        const int err = errno;
        ::close(srcFd);
        return failureVoid(err);
    }

    uint8_t buffer[4096];
    while (true) {
        const ssize_t readCount = ::read(srcFd, buffer, sizeof(buffer));
        if (readCount < 0) {
            if (errno == EINTR) {
                continue;
            }
            const int err = errno;
            ::close(srcFd);
            ::close(destFd);
            ::unlink(destPath.c_str());
            return failureVoid(err);
        }
        if (readCount == 0) {
            break;
        }
        const auto writeResult = writeAll(destFd, buffer, static_cast<size_t>(readCount));
        if (doof::is_failure(writeResult)) {
            ::close(srcFd);
            ::close(destFd);
            ::unlink(destPath.c_str());
            return writeResult;
        }
    }

    const int srcClose = ::close(srcFd);
    const int destClose = ::close(destFd);
    if (srcClose != 0) {
        ::unlink(destPath.c_str());
        return failureVoid(errno);
    }
    if (destClose != 0) {
        ::unlink(destPath.c_str());
        return failureVoid(errno);
    }
    return doof::Success<void>{};
}

} // namespace doof_fs

class NativeBlobReadStream {
public:
    static doof::Result<std::shared_ptr<NativeBlobReadStream>, IoError> open(const std::string& path, int32_t blockSize) {
        const auto opened = doof_fs::NativeBlobReadStream::open(path, blockSize);
        if (doof::is_failure(opened)) {
            return doof::Failure<IoError>{doof::failure_error(opened)};
        }

        return doof::Success<std::shared_ptr<NativeBlobReadStream>>{std::shared_ptr<NativeBlobReadStream>(new NativeBlobReadStream(doof::success_value(opened)))};
    }

    std::shared_ptr<std::vector<uint8_t>> next() {
        return native_->next();
    }

private:
    explicit NativeBlobReadStream(std::shared_ptr<doof_fs::NativeBlobReadStream> native)
        : native_(std::move(native)) {}

    std::shared_ptr<doof_fs::NativeBlobReadStream> native_;
};

class NativeFileWriteStream {
public:
    static doof::Result<std::shared_ptr<NativeFileWriteStream>, IoError> open(const std::string& path) {
        const auto opened = doof_fs::NativeFileWriteStream::open(path);
        if (doof::is_failure(opened)) {
            return doof::Failure<IoError>{doof::failure_error(opened)};
        }

        return doof::Success<std::shared_ptr<NativeFileWriteStream>>{std::shared_ptr<NativeFileWriteStream>(new NativeFileWriteStream(doof::success_value(opened)))};
    }

    doof::Result<void, IoError> writeBlob(const std::shared_ptr<std::vector<uint8_t>>& data) {
        return native_->writeBlob(data);
    }

    doof::Result<void, IoError> writeLine(const std::string& line) {
        return native_->writeLine(line);
    }

    doof::Result<void, IoError> close() {
        return native_->close();
    }

private:
    explicit NativeFileWriteStream(std::shared_ptr<doof_fs::NativeFileWriteStream> native)
        : native_(std::move(native)) {}

    std::shared_ptr<doof_fs::NativeFileWriteStream> native_;
};
