// Public barrel for the fs package.

import { resourcePath } from "std/path"
import { blobStreamToLineStream } from "std/stream"

export {
  EntryKind, FileInfo, IoError,
} from "./types"

// Native POSIX-oriented filesystem interop.

import { FileInfo, IoError } from "./types"

export import isolated function readText(path: string): Result<string, IoError> from "native_fs.hpp" as doof_fs::readText
export import isolated function writeText(path: string, content: string): Result<none, IoError> from "native_fs.hpp" as doof_fs::writeText
export import isolated function readBlob(path: string): Result<readonly byte[], IoError> from "native_fs.hpp" as doof_fs::readBlob
export import isolated function writeBlob(path: string, data: readonly byte[]): Result<none, IoError> from "native_fs.hpp" as doof_fs::writeBlob
export import isolated function appendText(path: string, content: string): Result<none, IoError> from "native_fs.hpp" as doof_fs::appendText
export import isolated function appendBlob(path: string, data: readonly byte[]): Result<none, IoError> from "native_fs.hpp" as doof_fs::appendBlob

function resolveResourcePath(path: string): Result<string, IoError> {
  resolvedPath := resourcePath(path) else {
    return Failure(.InvalidPath)
  }
  return Success(resolvedPath)
}

export function readTextResource(path: string): Result<string, IoError> {
  try resolved := resolveResourcePath(path)
  return readText(resolved)
}

export function readBlobResource(path: string): Result<readonly byte[], IoError> {
  try resolved := resolveResourcePath(path)
  return readBlob(resolved)
}

import class NativeBlobReadStream from "native_fs.hpp" as NativeBlobReadStream {
  isolated static open(path: string, blockSize: int): Result<NativeBlobReadStream, IoError>
  isolated next(): readonly byte[] | none
}

import class NativeFileWriteStream from "native_fs.hpp" as NativeFileWriteStream {
  isolated static open(path: string): Result<NativeFileWriteStream, IoError>
  isolated writeBlob(data: readonly byte[]): Result<none, IoError>
  isolated writeLine(line: string): Result<none, IoError>
  isolated close(): Result<none, IoError>
}

function normalizeStreamBlockSize(blockSize: int): int {
  if blockSize > 0 {
    return blockSize
  }

  return 65536
}

class BlockReadStream implements Stream<readonly byte[]> {
  native: NativeBlobReadStream
  currentValue: readonly byte[] = []

  next(): bool {
    chunk := native.next()
    if chunk == none {
      return false
    }
    currentValue = chunk!
    return true
  }

  value(): readonly byte[] => currentValue
}

export function readBlockStream(path: string, blockSize: int = 65536): Result<Stream<readonly byte[]>, IoError> {
  try native := NativeBlobReadStream.open(path, normalizeStreamBlockSize(blockSize))
  return Success(BlockReadStream {
    native,
  })
}

export function readBlobStream(path: string, blockSize: int = 65536): Result<Stream<readonly byte[]>, IoError> {
  return readBlockStream(path, blockSize)
}

export function readLineStream(path: string, blockSize: int = 65536): Result<Stream<string>, IoError> {
  try blocks := readBlockStream(path, blockSize)
  return Success(blobStreamToLineStream(blocks))
}

export function readResourceBlockStream(path: string, blockSize: int = 65536): Result<Stream<readonly byte[]>, IoError> {
  try resolved := resolveResourcePath(path)
  return readBlockStream(resolved, blockSize)
}

export function readResourceBlobStream(path: string, blockSize: int = 65536): Result<Stream<readonly byte[]>, IoError> {
  return readResourceBlockStream(path, blockSize)
}

export function readResourceLineStream(path: string, blockSize: int = 65536): Result<Stream<string>, IoError> {
  try resolved := resolveResourcePath(path)
  return readLineStream(resolved, blockSize)
}

export function writeBlobStream(path: string, chunks: Stream<readonly byte[]>): Result<none, IoError> {
  try writer := NativeFileWriteStream.open(path)
  for chunk of chunks {
    try writer.writeBlob(chunk)
  }
  try writer.close()
  return Success()
}

export function writeLineStream(path: string, lines: Stream<string>): Result<none, IoError> {
  try writer := NativeFileWriteStream.open(path)
  for line of lines {
    try writer.writeLine(line)
  }
  try writer.close()
  return Success()
}

export import isolated function exists(path: string): bool from "native_fs.hpp" as doof_fs::exists
export import isolated function isFile(path: string): bool from "native_fs.hpp" as doof_fs::isFile
export import isolated function isDirectory(path: string): bool from "native_fs.hpp" as doof_fs::isDirectory
export import isolated function metadata(path: string): Result<FileInfo, IoError> from "native_fs.hpp" as doof_fs::metadata
export import isolated function readDir(path: string): Result<FileInfo[], IoError> from "native_fs.hpp" as doof_fs::readDir
export function readResourceDir(path: string): Result<FileInfo[], IoError> {
  try resolved := resolveResourcePath(path)
  return readDir(resolved)
}
export import isolated function mkdir(path: string): Result<none, IoError> from "native_fs.hpp" as doof_fs::mkdir
export import isolated function remove(path: string): Result<none, IoError> from "native_fs.hpp" as doof_fs::remove
export import isolated function rename(sourcePath: string, destPath: string): Result<none, IoError> from "native_fs.hpp" as doof_fs::rename
export import isolated function copy(sourcePath: string, destPath: string): Result<none, IoError> from "native_fs.hpp" as doof_fs::copy
