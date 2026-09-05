# Random-access files

`File` is a persistent, seekable binary file in `std/fs`. It owns one cursor and
an optional whole-file lock. Typed values and text encoding use `std/blob`.

```doof
import { File } from "std/fs"

file := try File {
  path: "records.bin",
  mode: .ReadWrite,
  create: true,
  lock: .Exclusive,
}
try file.setPosition(16L)
try file.writeLong(123456L)
try file.flush()
try file.close()
```

## Construction

`File(path: string, mode: FileMode = .ReadOnly, create: bool = false,
lock: FileLock = .None, waitForLock: bool = true,
endianness: Endian = .LittleEndian): Result<File, IoError>`

- `FileMode.ReadOnly` permits reads and seeking. `ReadWrite` also permits writes,
  resizing, and flushing.
- `create: true` creates a missing file and preserves an existing file. It
  requires `ReadWrite`. Construction never truncates; use `truncate(0L)` after
  acquiring an exclusive lock when replacing contents.
- `FileLock.None`, `Shared`, and `Exclusive` select lifetime locking. Exclusive
  requires `ReadWrite`. A shared-locked handle rejects writes, resizing, and
  flushing even when opened with `ReadWrite`.
- Construction waits for a conflicting lock by default. `waitForLock: false`
  returns `IoError.WouldBlock` instead. An interrupted POSIX operation returns
  `Interrupted`; there is no timeout or cancellation API in this version.
- Failed construction closes the underlying handle. If construction created a
  new file before a subsequent failure, that file remains on disk.
- Only regular files are supported. Directories and non-seekable devices are
  rejected. Paths follow symlinks. `Endian` and text encoding types are imported
  from `std/blob`.

## Cursor and byte operations

| Method | Result success value | Behavior |
| --- | --- | --- |
| `getPosition()` | `long` | Current absolute byte offset |
| `setPosition(position: long)` | `none` | Seek; does not change file length |
| `length()` | `long` | Current length from the open handle |
| `remaining()` | `long` | Length minus position, clamped to zero |
| `readBytes(length: long)` | `readonly byte[]` | Read exactly the requested length |
| `readUpTo(length: long)` | `readonly byte[]` | Read up to the requested length, at most 65536 bytes per call; empty at EOF |
| `writeBytes(data: readonly byte[])` | `none` | Write all bytes at the cursor, extending the file when needed |
| `truncate(length: long)` | `none` | Shrink or extend the file, preserving the cursor |
| `flush()` | `none` | Request OS synchronization of file data and metadata |
| `close()` | `none` | Release the file and lock; repeated calls succeed |

All these methods return `Result<..., IoError>`. Positions and lengths are
64-bit and non-negative. Seeking past EOF is allowed; subsequently writing
leaves a zero-filled gap. Extending with `truncate` also produces zero bytes.
There is no application-level buffering.

Exact reads, including typed reads, fail with `UnexpectedEof` if incomplete.
A failed read or write may have advanced the cursor by the bytes transferred;
writes may have partially modified the file. There is no rollback. A successful
zero-length read returns an empty array. `close` invalidates the handle even if
closing reports an error. Operations on a closed handle return `Closed`.

## Typed values and text

The following paired `readX()` / `writeX(value)` methods use the same types,
widths, endianness, and numeric range behavior as `BlobReader` / `BlobBuilder`:

| Suffix | Doof type | Bytes |
| --- | --- | --- |
| `Byte` | `byte` | 1 |
| `SignedByte` | `int` | 1 |
| `Bool` | `bool` | 1 |
| `Short` | `int` | 2 |
| `UnsignedShort` | `int` | 2 |
| `Int` | `int` | 4 |
| `UnsignedInt` | `long` | 4 |
| `Long` | `long` | 8 |
| `Float` | `float` | 4 |
| `Double` | `double` | 8 |

Reads return `Result<T, IoError>` and writes return `Result<none, IoError>`.
`readString(length)` / `writeString(value)` provide blob-compatible raw UTF-8
strings without a length prefix, also returning I/O results.

`readText(length, encoding = .Utf8)` returns
`Result<string, IoError | EncodingError>`; `writeText(value, encoding = .Utf8)`
returns `Result<int, IoError | EncodingError>`, with the encoded byte count on
success. Encoding failure happens before writing; decoding failure occurs after
the bytes have been read. `readTextLossy` and `writeTextLossy` accept the same
arguments but return only `IoError` failures. Lossy writes return the byte count.

## Lock ownership and portability

Locks last until explicit `close()` or destruction of the last reference.
Assigning a `File` to another variable shares the handle, cursor, and lock;
closing either reference closes it for both. Use one handle serially, or keep it
inside one actor; methods do not synchronize concurrent use of the same handle.
No public unlock, lock conversion, or byte-range locking API is provided.

macOS and Linux use `flock`; Windows uses `LockFileEx` over the entire supported
file offset range, including future growth. Handles are not inherited by newly
executed child programs. Process termination releases their locks.

On local POSIX filesystems locks are advisory: all cooperating processes must
lock before accessing data. Windows locks additionally restrict ordinary I/O
through other handles. Do not depend on preventing non-cooperating I/O across
platforms. Network filesystems can have different locking behavior and are not
covered by the local-filesystem guarantee.

Locks refer to the opened file, not its pathname. Renaming or replacing that
path does not transfer the lock to a replacement file. These locks are intended
for in-place access, not coordination of atomic path replacement. Unlocking or
closing is not a durability guarantee; explicitly `flush()` when required.

## Validation

Run `doof test fs` from the stdlib workspace. When developing against these
sources, set `DOOF_STDLIB_ROOT` to the workspace absolute path. The process test
builds a Doof worker with the `doof` executable on PATH and uses bounded waits.
Run the suite on macOS, Linux, and Windows for native behavior validation.
