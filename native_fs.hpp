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
    return doof::Result<T, IoError>::failure(mapErrno(err));
}

inline doof::Result<void, IoError> failureVoid(int err) {
    return doof::Result<void, IoError>::failure(mapErrno(err));
}

inline std::string joinPath(const std::string& dirPath, const std::string& entryName) {
    if (dirPath.empty() || dirPath.back() == '/') {
        return dirPath + entryName;
    }
    return dirPath + "/" + entryName;
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

inline doof::Result<std::shared_ptr<std::vector<uint8_t>>, IoError> readBytes(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Result<std::shared_ptr<std::vector<uint8_t>>, IoError>::failure(IoError::InvalidPath);
    }

    int fd = ::open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return failureResult<std::shared_ptr<std::vector<uint8_t>>>(errno);
    }

    struct stat st {};
    if (::fstat(fd, &st) != 0) {
        const int err = errno;
        ::close(fd);
        return failureResult<std::shared_ptr<std::vector<uint8_t>>>(err);
    }
    if (S_ISDIR(st.st_mode)) {
        ::close(fd);
        return doof::Result<std::shared_ptr<std::vector<uint8_t>>, IoError>::failure(IoError::IsDirectory);
    }

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
    return doof::Result<std::shared_ptr<std::vector<uint8_t>>, IoError>::success(data);
}

inline doof::Result<std::string, IoError> readText(const std::string& path) {
    const auto raw = readBytes(path);
    if (raw.isFailure()) {
        return doof::Result<std::string, IoError>::failure(raw.error());
    }

    const auto& bytes = *raw.value();
    return doof::Result<std::string, IoError>::success(std::string(bytes.begin(), bytes.end()));
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
    return doof::Result<void, IoError>::success();
}

inline doof::Result<void, IoError> writeText(const std::string& path, const std::string& content) {
    if (isInvalidPath(path)) {
        return doof::Result<void, IoError>::failure(IoError::InvalidPath);
    }

    const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd < 0) {
        return failureVoid(errno);
    }

    const auto result = writeAll(fd, reinterpret_cast<const uint8_t*>(content.data()), content.size());
    const int closeResult = ::close(fd);
    if (result.isFailure()) {
        return result;
    }
    if (closeResult != 0) {
        return failureVoid(errno);
    }
    return doof::Result<void, IoError>::success();
}

inline doof::Result<void, IoError> writeBytes(
    const std::string& path,
    const std::shared_ptr<std::vector<uint8_t>>& data
) {
    if (isInvalidPath(path)) {
        return doof::Result<void, IoError>::failure(IoError::InvalidPath);
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
    if (result.isFailure()) {
        return result;
    }
    if (closeResult != 0) {
        return failureVoid(errno);
    }
    return doof::Result<void, IoError>::success();
}

inline doof::Result<void, IoError> appendText(const std::string& path, const std::string& content) {
    if (isInvalidPath(path)) {
        return doof::Result<void, IoError>::failure(IoError::InvalidPath);
    }

    const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) {
        return failureVoid(errno);
    }

    const auto result = writeAll(fd, reinterpret_cast<const uint8_t*>(content.data()), content.size());
    const int closeResult = ::close(fd);
    if (result.isFailure()) {
        return result;
    }
    if (closeResult != 0) {
        return failureVoid(errno);
    }
    return doof::Result<void, IoError>::success();
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

inline doof::Result<std::shared_ptr<std::vector<std::shared_ptr<DirEntry>>>, IoError> readDir(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Result<std::shared_ptr<std::vector<std::shared_ptr<DirEntry>>>, IoError>::failure(IoError::InvalidPath);
    }

    DIR* dir = ::opendir(path.c_str());
    if (!dir) {
        return failureResult<std::shared_ptr<std::vector<std::shared_ptr<DirEntry>>>>(errno);
    }

    auto entries = std::make_shared<std::vector<std::shared_ptr<DirEntry>>>();
    while (true) {
        errno = 0;
        dirent* rawEntry = ::readdir(dir);
        if (!rawEntry) {
            if (errno != 0) {
                const int err = errno;
                ::closedir(dir);
                return failureResult<std::shared_ptr<std::vector<std::shared_ptr<DirEntry>>>>(err);
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
            return failureResult<std::shared_ptr<std::vector<std::shared_ptr<DirEntry>>>>(err);
        }

        const int64_t size = S_ISREG(st.st_mode) ? static_cast<int64_t>(st.st_size) : 0;
        const int64_t modifiedAt = static_cast<int64_t>(st.st_mtime);
        entries->push_back(std::make_shared<DirEntry>(
            name,
            entryKindFromMode(st.st_mode),
            size,
            modifiedAt
        ));
    }

    ::closedir(dir);
    return doof::Result<std::shared_ptr<std::vector<std::shared_ptr<DirEntry>>>, IoError>::success(entries);
}

inline doof::Result<void, IoError> mkdir(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Result<void, IoError>::failure(IoError::InvalidPath);
    }
    if (::mkdir(path.c_str(), 0777) != 0) {
        return failureVoid(errno);
    }
    return doof::Result<void, IoError>::success();
}

inline doof::Result<void, IoError> remove(const std::string& path) {
    if (isInvalidPath(path)) {
        return doof::Result<void, IoError>::failure(IoError::InvalidPath);
    }

    struct stat st {};
    if (::lstat(path.c_str(), &st) != 0) {
        return failureVoid(errno);
    }

    const int rc = S_ISDIR(st.st_mode) ? ::rmdir(path.c_str()) : ::unlink(path.c_str());
    if (rc != 0) {
        return failureVoid(errno);
    }
    return doof::Result<void, IoError>::success();
}

inline doof::Result<void, IoError> rename(const std::string& sourcePath, const std::string& destPath) {
    if (isInvalidPath(sourcePath) || isInvalidPath(destPath)) {
        return doof::Result<void, IoError>::failure(IoError::InvalidPath);
    }
    if (::rename(sourcePath.c_str(), destPath.c_str()) != 0) {
        return failureVoid(errno);
    }
    return doof::Result<void, IoError>::success();
}

inline doof::Result<void, IoError> copy(const std::string& sourcePath, const std::string& destPath) {
    if (isInvalidPath(sourcePath) || isInvalidPath(destPath)) {
        return doof::Result<void, IoError>::failure(IoError::InvalidPath);
    }

    struct stat srcStat {};
    if (::stat(sourcePath.c_str(), &srcStat) != 0) {
        return failureVoid(errno);
    }
    if (S_ISDIR(srcStat.st_mode)) {
        return doof::Result<void, IoError>::failure(IoError::IsDirectory);
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
        if (writeResult.isFailure()) {
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
    return doof::Result<void, IoError>::success();
}

} // namespace doof_fs