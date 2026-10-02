import { File, IoError, FileLock, FileMode, writeBlob, remove } from "../index"
import { BlobBuilder, Endian, TextEncoding } from "std/blob"

function expectError<T>(result: Result<T, IoError>, expected: IoError): none {
  case result {
    _: Success -> assert(false, "expected I/O failure"),
    f: Failure -> assert(f.error == expected, "unexpected I/O error")
  }
}

export function testFileCursorAndLifetime(): none {
  path := "build/tests/random-access.bin"
  writeBlob(path, [1, 2, 3])!
  file := File { path, mode: .ReadWrite, create: true, lock: .Exclusive }!
  assert((file.length()!) == 3L, "create must preserve contents")
  file.setPosition(1L)!
  file.writeByte(9)!
  file.setPosition(0L)!
  assert((file.readByte()!) == 1, "file behavior mismatch")
  assert((file.readByte()!) == 9, "file behavior mismatch")
  expectError(file.readInt(), .UnexpectedEof)
  assert((file.getPosition()!) == 3L, "file behavior mismatch")
  assert((file.readUpTo(10L)!).length == 0L, "file behavior mismatch")
  file.setPosition(10L)!
  assert((file.length()!) == 3L, "seeking alone must not extend")
  file.writeByte(7)!
  file.setPosition(3L)!
  bytes := file.readBytes(8L)!
  for index of 0..<7 { assert(bytes[index] == 0, "file behavior mismatch") }
  assert(bytes[7] == 7, "file behavior mismatch")
  file.truncate(2L)!
  assert((file.getPosition()!) == 11L, "file behavior mismatch")
  assert((file.remaining()!) == 0L, "file behavior mismatch")
  file.flush()!
  expectError(file.setPosition(-1L), .InvalidArgument)
  expectError(file.readBytes(-1L), .InvalidArgument)
  expectError(file.truncate(-1L), .InvalidArgument)
  file.close()!
  file.close()!
  expectError(file.readByte(), .Closed)
  expectError(file.length(), .Closed)
  expectError(file.writeByte(1), .Closed)
  remove(path)!
}

export function testFileLockAndAccessModes(): none {
  path := "build/tests/locking.bin"
  writeBlob(path, [])!
  expectError(File { path, create: true }, .InvalidArgument)
  expectError(File { path, lock: .Exclusive }, .InvalidArgument)
  first := File { path, lock: .Shared }!
  second := File { path, mode: .ReadWrite, lock: .Shared, waitForLock: false }!
  expectError(second.writeByte(1), .PermissionDenied)
  expectError(first.truncate(0L), .PermissionDenied)
  expectError(File { path, mode: .ReadWrite, lock: .Exclusive, waitForLock: false }, .WouldBlock)
  first.close()!
  expectError(File { path, mode: .ReadWrite, lock: .Exclusive, waitForLock: false }, .WouldBlock)
  second.close()!
  holdExclusive(path)
  afterScope := File { path, lock: .Shared, waitForLock: false }!
  assert((afterScope.readByte()!) == 42, "file behavior mismatch")
  afterScope.close()!
  remove(path)!
}

export function testFileTypedBlobCompatibility(): none {
  for endian of [Endian.LittleEndian, Endian.BigEndian] {
    path := "build/tests/typed-file.bin"
    file := File { path, mode: .ReadWrite, create: true, lock: .Exclusive, endianness: endian }!
    file.truncate(0L)!
    builder := BlobBuilder { endianness: endian }
    file.writeByte(255)!
    builder.writeByte(255)
    file.writeSignedByte(-17)!
    builder.writeSignedByte(-17)
    file.writeBool(true)!
    builder.writeBool(true)
    file.writeShort(-1234)!
    builder.writeShort(-1234)
    file.writeUnsignedShort(65535)!
    builder.writeUnsignedShort(65535)
    file.writeInt(-123456)!
    builder.writeInt(-123456)
    file.writeUnsignedInt(4294967295L)!
    builder.writeUnsignedInt(4294967295L)
    file.writeLong(1234567890123L)!
    builder.writeLong(1234567890123L)
    file.writeFloat(1.5)!
    builder.writeFloat(1.5)
    file.writeDouble(2.25)!
    builder.writeDouble(2.25)
    file.writeString("hello")!
    builder.writeString("hello")
    assert((file.writeText("café", .Windows1252)!) == 4, "file behavior mismatch")
    builder.writeText("café", .Windows1252)!
    expected := builder.build()
    file.setPosition(0L)!
    actual := file.readBytes(expected.length)!
    for index of 0..<expected.length { assert(actual[index] == expected[index], "file behavior mismatch") }
    file.setPosition(0L)!
    assert((file.readByte()!) == 255, "file behavior mismatch")
    assert((file.readSignedByte()!) == -17, "file behavior mismatch")
    assert((file.readBool()!) == true, "file behavior mismatch")
    assert((file.readShort()!) == -1234, "file behavior mismatch")
    assert((file.readUnsignedShort()!) == 65535, "file behavior mismatch")
    assert((file.readInt()!) == -123456, "file behavior mismatch")
    assert((file.readUnsignedInt()!) == 4294967295L, "file behavior mismatch")
    assert((file.readLong()!) == 1234567890123L, "file behavior mismatch")
    assert((file.readFloat()!) == 1.5, "file behavior mismatch")
    assert((file.readDouble()!) == 2.25, "file behavior mismatch")
    assert((file.readString(5L)!) == "hello", "file behavior mismatch")
    assert((file.readText(4L, .Windows1252)!) == "café", "file behavior mismatch")
    file.close()!
    remove(path)!
  }
}

export function testFileLargeOffsets(): none {
  path := "build/tests/large-offset.bin"
  file := File { path, mode: .ReadWrite, create: true }!
  file.truncate(0L)!
  file.setPosition(4294967296L)!
  file.writeByte(3)!
  assert((file.length()!) == 4294967297L, "file behavior mismatch")
  file.setPosition(4294967296L)!
  assert((file.readByte()!) == 3, "file behavior mismatch")
  file.close()!
  remove(path)!
}

function holdExclusive(path: string): none {
  exclusive := File { path, mode: .ReadWrite, lock: .Exclusive, waitForLock: false }!
  expectError(File { path, lock: .Shared, waitForLock: false }, .WouldBlock)
  exclusive.writeByte(42)!
}

export function testFileCreationAndEncodingFailures(): none {
  path := "build/tests/new-file.bin"
  // Earlier successful runs remove this fixture.
  expectError(File(path), .NotFound)
  file := File { path, mode: .ReadWrite, create: true }!
  assert((file.length()!) == 0L, "new file starts empty")
  assert((file.readBytes(0L)!).length == 0L, "zero-byte read succeeds at EOF")
  case file.writeText("€", .Ascii) {
    _: Success -> assert(false, "strict encoding must reject unrepresentable text"),
    _: Failure -> assert((file.length()!) == 0L, "encoding failure must not write")
  }
  assert((file.writeTextLossy("€", .Ascii)!) == 1, "lossy text returns byte count")
  file.setPosition(0L)!
  assert((file.readTextLossy(1L, .Ascii)!) == "?", "lossy replacement matches blob")
  file.setPosition(0L)!
  file.writeByte(255)!
  file.setPosition(0L)!
  case file.readText(1L, .Utf8) {
    _: Success -> assert(false, "strict decoding must reject malformed UTF-8"),
    _: Failure -> assert((file.getPosition()!) == 1L, "decoding occurs after bytes are read")
  }
  alias := file
  alias.close()!
  expectError(file.getPosition(), .Closed)
  remove(path)!
}
