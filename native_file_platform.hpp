#pragma once

// Small OS adapter. Descriptors are private and never inherited across exec.
#include "doof_runtime.hpp"
#include <cerrno>
#include <cstdint>
#include <fcntl.h>
#include <sys/stat.h>
#include <memory>
#include <string>
#include <vector>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <io.h>
#else
#include <unistd.h>
#endif
#include <algorithm>
#include <limits>
#if defined(_WIN32)
#include <share.h>
#else
#include <sys/file.h>
#endif

namespace doof_fs::file_platform {
inline IoError error(int err) {
    switch (err) {
        case ENOENT: return IoError::NotFound;
        case EACCES: case EPERM: return IoError::PermissionDenied;
        case EEXIST: return IoError::AlreadyExists;
        case EISDIR: return IoError::IsDirectory;
        case ENOTDIR: return IoError::NotDirectory;
        case EINVAL: return IoError::InvalidArgument;
        case ENAMETOOLONG: return IoError::InvalidPath;
        case EINTR: return IoError::Interrupted;
        default: return IoError::Other;
    }
}
template<typename T> inline doof::Result<T, IoError> failure(int err) {
    return doof::Failure<IoError>{error(err)};
}
inline doof::Result<int64_t, IoError> length(int fd) {
#if defined(_WIN32)
    struct _stat64 info{};
    if (_fstat64(fd, &info) != 0) return failure<int64_t>(errno);
    if ((info.st_mode & _S_IFMT) == _S_IFDIR) return doof::Failure<IoError>{IoError::IsDirectory};
    if ((info.st_mode & _S_IFMT) != _S_IFREG) return doof::Failure<IoError>{IoError::Unsupported};
#else
    struct stat info{};
    if (::fstat(fd, &info) != 0) return failure<int64_t>(errno);
    if (S_ISDIR(info.st_mode)) return doof::Failure<IoError>{IoError::IsDirectory};
    if (!S_ISREG(info.st_mode)) return doof::Failure<IoError>{IoError::Unsupported};
#endif
    return doof::Success<int64_t>{static_cast<int64_t>(info.st_size)};
}
inline int open(const std::string& path, bool writable, bool create) {
    int flags = writable ? O_RDWR : O_RDONLY;
    if (create) flags |= O_CREAT;
#if defined(_WIN32)
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.data(), static_cast<int>(path.size()), nullptr, 0);
    if (count == 0) { errno = EINVAL; return -1; }
    std::wstring wide(count, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.data(), static_cast<int>(path.size()), wide.data(), count);
    int fd = -1;
    errno_t err = _wsopen_s(&fd, wide.c_str(), flags | _O_BINARY | _O_NOINHERIT, _SH_DENYNO, _S_IREAD | _S_IWRITE);
    if (err) errno = err;
    return fd;
#else
    return ::open(path.c_str(), flags | O_CLOEXEC | O_NONBLOCK, 0666);
#endif
}
inline int close(int fd) {
#if defined(_WIN32)
    return _close(fd);
#else
    return ::close(fd);
#endif
}
inline int64_t seek(int fd, int64_t offset, int origin) {
#if defined(_WIN32)
    return _lseeki64(fd, offset, origin);
#else
    static_assert(sizeof(off_t) >= 8, "File requires 64-bit offsets");
    return ::lseek(fd, offset, origin);
#endif
}
inline int64_t read(int fd, uint8_t* data, size_t size) {
#if defined(_WIN32)
    return _read(fd, data, static_cast<unsigned int>(size));
#else
    return ::read(fd, data, size);
#endif
}
inline int64_t write(int fd, const uint8_t* data, size_t size) {
#if defined(_WIN32)
    return _write(fd, data, static_cast<unsigned int>(size));
#else
    return ::write(fd, data, size);
#endif
}
inline int truncate(int fd, int64_t size) {
#if defined(_WIN32)
    const auto err = _chsize_s(fd, size);
    if (err) { errno = static_cast<int>(err); return -1; }
    return 0;
#else
    return ::ftruncate(fd, size);
#endif
}
inline int flush(int fd) {
#if defined(_WIN32)
    return _commit(fd);
#else
    return ::fsync(fd);
#endif
}
inline doof::Result<void, IoError> lock(int fd, bool exclusive, bool wait) {
#if defined(_WIN32)
    OVERLAPPED range{};
    DWORD flags = exclusive ? LOCKFILE_EXCLUSIVE_LOCK : 0;
    if (!wait) flags |= LOCKFILE_FAIL_IMMEDIATELY;
    // Cover every supported offset, including future growth, through one lock.
    if (!LockFileEx(reinterpret_cast<HANDLE>(_get_osfhandle(fd)), flags, 0, MAXDWORD, MAXDWORD, &range)) {
        DWORD err = GetLastError();
        if (err == ERROR_LOCK_VIOLATION) return doof::Failure<IoError>{IoError::WouldBlock};
        return doof::Failure<IoError>{err == ERROR_ACCESS_DENIED ? IoError::PermissionDenied : IoError::Other};
    }
#else
    if (::flock(fd, (exclusive ? LOCK_EX : LOCK_SH) | (wait ? 0 : LOCK_NB)) != 0) {
        if (errno == EWOULDBLOCK || errno == EAGAIN) return doof::Failure<IoError>{IoError::WouldBlock};
        return failure<void>(errno);
    }
#endif
    return doof::Success<void>{};
}
} // namespace doof_fs::file_platform
