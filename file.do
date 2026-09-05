import { BlobBuilder, BlobReader, Endian, TextEncoding, EncodingError } from "std/blob"
import { IoError, FileMode, FileLock } from "./types"

import class NativeFile from "native_file.hpp" as doof_fs::NativeFile {
  isolated static open(path: string, mode: FileMode, create: bool, lock: FileLock, waitForLock: bool): Result<NativeFile, IoError>
  isolated getPosition(): Result<long, IoError>
  isolated setPosition(position: long): Result<none, IoError>
  isolated length(): Result<long, IoError>
  isolated readBytes(length: long, exact: bool): Result<readonly byte[], IoError>
  isolated writeBytes(data: readonly byte[]): Result<none, IoError>
  isolated truncate(length: long): Result<none, IoError>
  isolated flush(): Result<none, IoError>
  isolated close(): Result<none, IoError>
}

// One cursor and optional whole-file lock, owned for the handle's lifetime.
export class File {
  private native: NativeFile
  private endianness: Endian

  isolated static constructor(path: string, mode: FileMode = .ReadOnly, create: bool = false, lock: FileLock = .None, waitForLock: bool = true, endianness: Endian = .LittleEndian): Result<File, IoError> {
    try native := NativeFile.open(path, mode, create, lock, waitForLock)
    return Success(File { native, endianness })
  }

  isolated getPosition(): Result<long, IoError> => native.getPosition()
  isolated setPosition(position: long): Result<none, IoError> => native.setPosition(position)
  isolated length(): Result<long, IoError> => native.length()
  isolated readBytes(length: long): Result<readonly byte[], IoError> => native.readBytes(length, true)
  isolated readUpTo(length: long): Result<readonly byte[], IoError> => native.readBytes(length, false)
  isolated writeBytes(data: readonly byte[]): Result<none, IoError> => native.writeBytes(data)
  isolated truncate(length: long): Result<none, IoError> => native.truncate(length)
  isolated flush(): Result<none, IoError> => native.flush()
  isolated close(): Result<none, IoError> => native.close()

  isolated remaining(): Result<long, IoError> {
    try size := length()
    try position := getPosition()
    return Success(if position < size then size - position else 0L)
  }

  private isolated reader(length: long): Result<BlobReader, IoError> {
    try data := readBytes(length)
    return Success(BlobReader { data, endianness })
  }

  isolated readByte(): Result<byte, IoError> {
    try value := reader(1L)
    return Success(value.readByte())
  }
  isolated writeByte(value: byte): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeByte(value)
    return writeBytes(builder.build())
  }

  isolated readSignedByte(): Result<int, IoError> {
    try value := reader(1L)
    return Success(value.readSignedByte())
  }
  isolated writeSignedByte(value: int): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeSignedByte(value)
    return writeBytes(builder.build())
  }

  isolated readBool(): Result<bool, IoError> {
    try value := reader(1L)
    return Success(value.readBool())
  }
  isolated writeBool(value: bool): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeBool(value)
    return writeBytes(builder.build())
  }

  isolated readShort(): Result<int, IoError> {
    try value := reader(2L)
    return Success(value.readShort())
  }
  isolated writeShort(value: int): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeShort(value)
    return writeBytes(builder.build())
  }

  isolated readUnsignedShort(): Result<int, IoError> {
    try value := reader(2L)
    return Success(value.readUnsignedShort())
  }
  isolated writeUnsignedShort(value: int): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeUnsignedShort(value)
    return writeBytes(builder.build())
  }

  isolated readInt(): Result<int, IoError> {
    try value := reader(4L)
    return Success(value.readInt())
  }
  isolated writeInt(value: int): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeInt(value)
    return writeBytes(builder.build())
  }

  isolated readUnsignedInt(): Result<long, IoError> {
    try value := reader(4L)
    return Success(value.readUnsignedInt())
  }
  isolated writeUnsignedInt(value: long): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeUnsignedInt(value)
    return writeBytes(builder.build())
  }

  isolated readLong(): Result<long, IoError> {
    try value := reader(8L)
    return Success(value.readLong())
  }
  isolated writeLong(value: long): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeLong(value)
    return writeBytes(builder.build())
  }

  isolated readFloat(): Result<float, IoError> {
    try value := reader(4L)
    return Success(value.readFloat())
  }
  isolated writeFloat(value: float): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeFloat(value)
    return writeBytes(builder.build())
  }

  isolated readDouble(): Result<double, IoError> {
    try value := reader(8L)
    return Success(value.readDouble())
  }
  isolated writeDouble(value: double): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeDouble(value)
    return writeBytes(builder.build())
  }

  isolated readString(length: long): Result<string, IoError> {
    try value := reader(length)
    return Success(value.readString(length))
  }
  isolated writeString(value: string): Result<none, IoError> {
    builder := BlobBuilder { endianness }
    builder.writeString(value)
    return writeBytes(builder.build())
  }
  isolated readText(length: long, encoding: TextEncoding = .Utf8): Result<string, IoError | EncodingError> {
    try value := reader(length)
    try text := value.readText(length, encoding)
    return Success(text)
  }
  isolated writeText(value: string, encoding: TextEncoding = .Utf8): Result<int, IoError | EncodingError> {
    builder := BlobBuilder { endianness }
    try count := builder.writeText(value, encoding)
    try writeBytes(builder.build())
    return Success(count)
  }
  isolated readTextLossy(length: long, encoding: TextEncoding = .Utf8): Result<string, IoError> {
    try value := reader(length)
    return Success(value.readTextLossy(length, encoding))
  }
  isolated writeTextLossy(value: string, encoding: TextEncoding = .Utf8): Result<int, IoError> {
    builder := BlobBuilder { endianness }
    count := builder.writeTextLossy(value, encoding)
    try writeBytes(builder.build())
    return Success(count)
  }
}
