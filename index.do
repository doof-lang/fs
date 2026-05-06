// Public barrel for the fs package.

import { blobStreamToLineStream } from "std/stream"

export {
  EntryKind, DirEntry, IoError,
} from "./types"

// Native POSIX-oriented filesystem interop.

import { DirEntry, IoError } from "./types"

export import function readText(path: string): Result<string, IoError> from "native_fs.hpp" as doof_fs::readText
export import function writeText(path: string, content: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::writeText
export import function readBlob(path: string): Result<readonly byte[], IoError> from "native_fs.hpp" as doof_fs::readBlob
export import function writeBlob(path: string, data: readonly byte[]): Result<void, IoError> from "native_fs.hpp" as doof_fs::writeBlob
export import function appendText(path: string, content: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::appendText
export import function appendBlob(path: string, data: readonly byte[]): Result<void, IoError> from "native_fs.hpp" as doof_fs::appendBlob

import class NativeBlobReadStream from "native_fs.hpp" as NativeBlobReadStream {
  static open(path: string, blockSize: int): Result<NativeBlobReadStream, IoError>
  next(): readonly byte[] | null
}

import class NativeFileWriteStream from "native_fs.hpp" as NativeFileWriteStream {
  static open(path: string): Result<NativeFileWriteStream, IoError>
  writeBlob(data: readonly byte[]): Result<void, IoError>
  writeLine(line: string): Result<void, IoError>
  close(): Result<void, IoError>
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
    chunk := this.native.next()
    if chunk == null {
      return false
    }
    this.currentValue = chunk!
    return true
  }

  value(): readonly byte[] => this.currentValue
}

export function readBlockStream(path: string, blockSize: int = 65536): Result<Stream<readonly byte[]>, IoError> {
  try native := NativeBlobReadStream.open(path, normalizeStreamBlockSize(blockSize))
  let stream: Stream<readonly byte[]> = BlockReadStream {
    native,
  }
  return Success {
    value: stream
  }
}

export function readBlobStream(path: string, blockSize: int = 65536): Result<Stream<readonly byte[]>, IoError> {
  return readBlockStream(path, blockSize)
}

export function readLineStream(path: string, blockSize: int = 65536): Result<Stream<string>, IoError> {
  try blocks := readBlockStream(path, blockSize)
  let stream: Stream<string> = blobStreamToLineStream(blocks)
  return Success {
    value: stream
  }
}

export function writeBlobStream(path: string, chunks: Stream<readonly byte[]>): Result<void, IoError> {
  try writer := NativeFileWriteStream.open(path)
  for chunk of chunks {
    try writer.writeBlob(chunk)
  }
  try writer.close()
  return Success()
}

export function writeLineStream(path: string, lines: Stream<string>): Result<void, IoError> {
  try writer := NativeFileWriteStream.open(path)
  for line of lines {
    try writer.writeLine(line)
  }
  try writer.close()
  return Success()
}

export import function exists(path: string): bool from "native_fs.hpp" as doof_fs::exists
export import function isFile(path: string): bool from "native_fs.hpp" as doof_fs::isFile
export import function isDirectory(path: string): bool from "native_fs.hpp" as doof_fs::isDirectory
export import function readDir(path: string): Result<DirEntry[], IoError> from "native_fs.hpp" as doof_fs::readDir
export import function mkdir(path: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::mkdir
export import function remove(path: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::remove
export import function rename(sourcePath: string, destPath: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::rename
export import function copy(sourcePath: string, destPath: string): Result<void, IoError> from "native_fs.hpp" as doof_fs::copy