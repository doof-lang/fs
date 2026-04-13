// Native POSIX-oriented filesystem interop.

import { DirEntry, IoError } from "./types"

export import function readText(path: string): Result<string, IoError> from "native_fs.hpp" as doof_fs::readText
export import function writeText(path: string, content: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::writeText
export import function readBytes(path: string): Result<byte[], IoError> from "native_fs.hpp" as doof_fs::readBytes
export import function writeBytes(path: string, data: byte[]): Result<void, IoError> from "native_fs.hpp" as doof_fs::writeBytes
export import function appendText(path: string, content: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::appendText

export import function exists(path: string): bool from "native_fs.hpp" as doof_fs::exists
export import function isFile(path: string): bool from "native_fs.hpp" as doof_fs::isFile
export import function isDirectory(path: string): bool from "native_fs.hpp" as doof_fs::isDirectory
export import function readDir(path: string): Result<DirEntry[], IoError> from "native_fs.hpp" as doof_fs::readDir
export import function mkdir(path: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::mkdir
export import function remove(path: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::remove
export import function rename(sourcePath: string, destPath: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::rename
export import function copy(sourcePath: string, destPath: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::copy