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
  try! writeBlob(path, [1, 2, 3])
  file := try! File { path, mode: .ReadWrite, create: true, lock: .Exclusive }
  assert((try! file.length()) == 3L, "create must preserve contents")
  try! file.setPosition(1L)
  try! file.writeByte(9)
  try! file.setPosition(0L)
  assert((try! file.readByte()) == 1, "file behavior mismatch")
  assert((try! file.readByte()) == 9, "file behavior mismatch")
  expectError(file.readInt(), .UnexpectedEof)
  assert((try! file.getPosition()) == 3L, "file behavior mismatch")
  assert((try! file.readUpTo(10L)).length == 0L, "file behavior mismatch")
  try! file.setPosition(10L)
  assert((try! file.length()) == 3L, "seeking alone must not extend")
  try! file.writeByte(7)
  try! file.setPosition(3L)
  bytes := try! file.readBytes(8L)
  for index of 0..<7 { assert(bytes[index] == 0, "file behavior mismatch") }
  assert(bytes[7] == 7, "file behavior mismatch")
  try! file.truncate(2L)
  assert((try! file.getPosition()) == 11L, "file behavior mismatch")
  assert((try! file.remaining()) == 0L, "file behavior mismatch")
  try! file.flush()
  expectError(file.setPosition(-1L), .InvalidArgument)
  expectError(file.readBytes(-1L), .InvalidArgument)
  expectError(file.truncate(-1L), .InvalidArgument)
  try! file.close()
  try! file.close()
  expectError(file.readByte(), .Closed)
  expectError(file.length(), .Closed)
  expectError(file.writeByte(1), .Closed)
  try! remove(path)
}

export function testFileLockAndAccessModes(): none {
  path := "build/tests/locking.bin"
  try! writeBlob(path, [])
  expectError(File { path, create: true }, .InvalidArgument)
  expectError(File { path, lock: .Exclusive }, .InvalidArgument)
  first := try! File { path, lock: .Shared }
  second := try! File { path, mode: .ReadWrite, lock: .Shared, waitForLock: false }
  expectError(second.writeByte(1), .PermissionDenied)
  expectError(first.truncate(0L), .PermissionDenied)
  expectError(File { path, mode: .ReadWrite, lock: .Exclusive, waitForLock: false }, .WouldBlock)
  try! first.close()
  expectError(File { path, mode: .ReadWrite, lock: .Exclusive, waitForLock: false }, .WouldBlock)
  try! second.close()
  holdExclusive(path)
  afterScope := try! File { path, lock: .Shared, waitForLock: false }
  assert((try! afterScope.readByte()) == 42, "file behavior mismatch")
  try! afterScope.close()
  try! remove(path)
}

export function testFileTypedBlobCompatibility(): none {
  for endian of [Endian.LittleEndian, Endian.BigEndian] {
    path := "build/tests/typed-file.bin"
    file := try! File { path, mode: .ReadWrite, create: true, lock: .Exclusive, endianness: endian }
    try! file.truncate(0L)
    builder := BlobBuilder { endianness: endian }
    try! file.writeByte(255)
    builder.writeByte(255)
    try! file.writeSignedByte(-17)
    builder.writeSignedByte(-17)
    try! file.writeBool(true)
    builder.writeBool(true)
    try! file.writeShort(-1234)
    builder.writeShort(-1234)
    try! file.writeUnsignedShort(65535)
    builder.writeUnsignedShort(65535)
    try! file.writeInt(-123456)
    builder.writeInt(-123456)
    try! file.writeUnsignedInt(4294967295L)
    builder.writeUnsignedInt(4294967295L)
    try! file.writeLong(1234567890123L)
    builder.writeLong(1234567890123L)
    try! file.writeFloat(1.5)
    builder.writeFloat(1.5)
    try! file.writeDouble(2.25)
    builder.writeDouble(2.25)
    try! file.writeString("hello")
    builder.writeString("hello")
    assert((try! file.writeText("café", .Windows1252)) == 4, "file behavior mismatch")
    try! builder.writeText("café", .Windows1252)
    expected := builder.build()
    try! file.setPosition(0L)
    actual := try! file.readBytes(expected.length)
    for index of 0..<expected.length { assert(actual[index] == expected[index], "file behavior mismatch") }
    try! file.setPosition(0L)
    assert((try! file.readByte()) == 255, "file behavior mismatch")
    assert((try! file.readSignedByte()) == -17, "file behavior mismatch")
    assert((try! file.readBool()) == true, "file behavior mismatch")
    assert((try! file.readShort()) == -1234, "file behavior mismatch")
    assert((try! file.readUnsignedShort()) == 65535, "file behavior mismatch")
    assert((try! file.readInt()) == -123456, "file behavior mismatch")
    assert((try! file.readUnsignedInt()) == 4294967295L, "file behavior mismatch")
    assert((try! file.readLong()) == 1234567890123L, "file behavior mismatch")
    assert((try! file.readFloat()) == 1.5, "file behavior mismatch")
    assert((try! file.readDouble()) == 2.25, "file behavior mismatch")
    assert((try! file.readString(5L)) == "hello", "file behavior mismatch")
    assert((try! file.readText(4L, .Windows1252)) == "café", "file behavior mismatch")
    try! file.close()
    try! remove(path)
  }
}

export function testFileLargeOffsets(): none {
  path := "build/tests/large-offset.bin"
  file := try! File { path, mode: .ReadWrite, create: true }
  try! file.truncate(0L)
  try! file.setPosition(4294967296L)
  try! file.writeByte(3)
  assert((try! file.length()) == 4294967297L, "file behavior mismatch")
  try! file.setPosition(4294967296L)
  assert((try! file.readByte()) == 3, "file behavior mismatch")
  try! file.close()
  try! remove(path)
}

function holdExclusive(path: string): none {
  exclusive := try! File { path, mode: .ReadWrite, lock: .Exclusive, waitForLock: false }
  expectError(File { path, lock: .Shared, waitForLock: false }, .WouldBlock)
  try! exclusive.writeByte(42)
}

export function testFileCreationAndEncodingFailures(): none {
  path := "build/tests/new-file.bin"
  // Earlier successful runs remove this fixture.
  expectError(File(path), .NotFound)
  file := try! File { path, mode: .ReadWrite, create: true }
  assert((try! file.length()) == 0L, "new file starts empty")
  assert((try! file.readBytes(0L)).length == 0L, "zero-byte read succeeds at EOF")
  case file.writeText("€", .Ascii) {
    _: Success -> assert(false, "strict encoding must reject unrepresentable text"),
    _: Failure -> assert((try! file.length()) == 0L, "encoding failure must not write")
  }
  assert((try! file.writeTextLossy("€", .Ascii)) == 1, "lossy text returns byte count")
  try! file.setPosition(0L)
  assert((try! file.readTextLossy(1L, .Ascii)) == "?", "lossy replacement matches blob")
  try! file.setPosition(0L)
  try! file.writeByte(255)
  try! file.setPosition(0L)
  case file.readText(1L, .Utf8) {
    _: Success -> assert(false, "strict decoding must reject malformed UTF-8"),
    _: Failure -> assert((try! file.getPosition()) == 1L, "decoding occurs after bytes are read")
  }
  alias := file
  try! alias.close()
  expectError(file.getPosition(), .Closed)
  try! remove(path)
}
