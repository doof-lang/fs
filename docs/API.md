# std/fs Reference

`std/fs` is the POSIX-oriented filesystem package. It provides whole-file text
and byte I/O, streaming reads and writes, metadata queries, and basic directory
operations. Fallible operations return `Result<..., IoError>` so callers can
handle filesystem failures explicitly.

Use `std/path` for path string manipulation and application directory discovery.
Use `std/fs` once you want to touch the filesystem.

## Imports

```doof
import {
  EntryKind,
  FileInfo,
  IoError,
  appendBlob,
  appendText,
  copy,
  exists,
  isDirectory,
  isFile,
  metadata,
  mkdir,
  readBlob,
  readBlockStream,
  readBlobStream,
  readDir,
  readLineStream,
  readText,
  remove,
  rename,
  writeBlob,
  writeBlobStream,
  writeLineStream,
  writeText,
} from "std/fs"
```

## Data Types

### `EntryKind`

Classifies filesystem entries returned by `metadata` and `readDir`.

| Member | Value | Meaning |
| --- | ---: | --- |
| `File` | `0` | Regular file |
| `Directory` | `1` | Directory |
| `Symlink` | `2` | Symbolic link |
| `Other` | `3` | Device, pipe, socket, or another platform entry type |

Defined in [types.do](../types.do).

### `FileInfo`

Metadata returned by `metadata(path)` and each entry returned by `readDir(path)`.

| Field | Type | Notes |
| --- | --- | --- |
| `name` | `string` | Basename for `metadata`; entry name for `readDir`, not a full path |
| `kind` | `EntryKind` | Portable entry classification |
| `size` | `long` | Size in bytes for regular files; platform value for other entries |
| `modifiedAt` | `Instant` | Last modified timestamp |

Defined in [types.do](../types.do).

### `IoError`

Portable error category for filesystem operations.

| Member | Value | Typical cause |
| --- | ---: | --- |
| `NotFound` | `0` | Path does not exist |
| `PermissionDenied` | `1` | Process lacks permission |
| `AlreadyExists` | `2` | Creating or renaming over an existing target is not allowed by the operation |
| `IsDirectory` | `3` | File operation received a directory |
| `NotDirectory` | `4` | Directory operation received a non-directory path, or a parent component is not a directory |
| `InvalidPath` | `5` | Path is malformed or unsupported by the platform bridge |
| `Interrupted` | `6` | OS operation was interrupted |
| `Other` | `7` | Any platform error not represented above |

Defined in [types.do](../types.do).

## Whole-File I/O

Whole-file helpers are simplest when payloads fit comfortably in memory.

### `readText`

```doof
export import function readText(path: string): Result<string, IoError>
```

Read an entire file as UTF-8 text.

Use this for configuration files, small templates, and test fixtures. For large
logs or CSV-like input, prefer `readLineStream`.

### `writeText`

```doof
export import function writeText(path: string, content: string): Result<void, IoError>
```

Write text to a file, replacing any existing file contents. Parent directories
must already exist.

### `appendText`

```doof
export import function appendText(path: string, content: string): Result<void, IoError>
```

Append text to a file. Creates the file when it is absent.

### `readBlob`

```doof
export import function readBlob(path: string): Result<readonly byte[], IoError>
```

Read an entire file as raw bytes.

### `writeBlob`

```doof
export import function writeBlob(path: string, data: readonly byte[]): Result<void, IoError>
```

Write raw bytes to a file, replacing any existing file contents. Parent
directories must already exist.

### `appendBlob`

```doof
export import function appendBlob(path: string, data: readonly byte[]): Result<void, IoError>
```

Append raw bytes to a file. Creates the file when it is absent.

## Streaming I/O

Streaming helpers open the file first and return `Failure { error: IoError }`
if opening fails. Once a read stream has been returned, it is consumed through
Doof's `Stream<T>` interface.

The default `blockSize` is `65536` bytes. Passing `0` or a negative value uses
the same default.

### `readBlockStream`

```doof
export function readBlockStream(path: string, blockSize: int = 65536): Result<Stream<readonly byte[]>, IoError>
```

Open a file and return a stream of raw byte chunks.

```doof
chunks := try! readBlockStream("archive.bin", 131072)
for chunk of chunks {
  println("read ${chunk.length} bytes")
}
```

### `readBlobStream`

```doof
export function readBlobStream(path: string, blockSize: int = 65536): Result<Stream<readonly byte[]>, IoError>
```

Alias for `readBlockStream`. Use whichever name reads more clearly at the call
site.

### `readLineStream`

```doof
export function readLineStream(path: string, blockSize: int = 65536): Result<Stream<string>, IoError>
```

Open a file and return a stream of UTF-8 decoded lines.

Line handling is delegated to `std/stream.blobStreamToLineStream`:

- `\n`, `\r`, and `\r\n` are recognized as line endings.
- line endings are not included in returned strings.
- lines split across byte chunks are assembled.
- a final unterminated line is emitted.
- an empty file emits no lines.

```doof
lines := try! readLineStream("data.csv")
for line of lines {
  println(line)
}
```

### `writeBlobStream`

```doof
export function writeBlobStream(path: string, chunks: Stream<readonly byte[]>): Result<void, IoError>
```

Open a file for writing, consume all byte chunks, write them in order, close the
writer, and return the first `IoError` encountered. The destination is
overwritten. Parent directories must already exist.

### `writeLineStream`

```doof
export function writeLineStream(path: string, lines: Stream<string>): Result<void, IoError>
```

Open a file for writing, consume all strings, write each string followed by a
line feed (`\n`), close the writer, and return the first `IoError` encountered.

This normalizes line endings to LF:

```doof
input := try! readLineStream("mixed-endings.txt")
try! writeLineStream("normalized.txt", input)
```

## Metadata And Directory Operations

### `exists`

```doof
export import function exists(path: string): bool
```

Return `true` when the path exists as a file, directory, symlink, or other entry.
Use `metadata` when you need to distinguish "missing" from "not inspectable".

### `isFile`

```doof
export import function isFile(path: string): bool
```

Return `true` when the path exists and is a regular file.

### `isDirectory`

```doof
export import function isDirectory(path: string): bool
```

Return `true` when the path exists and is a directory.

### `metadata`

```doof
export import function metadata(path: string): Result<FileInfo, IoError>
```

Return metadata for one path. `FileInfo.name` is the path basename.

### `readDir`

```doof
export import function readDir(path: string): Result<FileInfo[], IoError>
```

Return direct entries in a directory. This does not recurse. Each
`FileInfo.name` is an entry name relative to the directory.

```doof
entries := try! readDir("assets")
for entry of entries {
  if entry.kind == EntryKind.File {
    println(entry.name)
  }
}
```

### `mkdir`

```doof
export import function mkdir(path: string): Result<void, IoError>
```

Create one directory. Parent directories must already exist. Existing targets
return `AlreadyExists` or another platform-specific `IoError`.

### `remove`

```doof
export import function remove(path: string): Result<void, IoError>
```

Remove a file or empty directory.

### `rename`

```doof
export import function rename(sourcePath: string, destPath: string): Result<void, IoError>
```

Move or rename a file or directory. Exact overwrite behavior is platform-defined
by the native bridge; handle `AlreadyExists` when the destination may already
exist.

### `copy`

```doof
export import function copy(sourcePath: string, destPath: string): Result<void, IoError>
```

Copy a file to a destination path. Parent directories for the destination must
already exist.

## Error Handling Patterns

Use `try!` or declaration `else` when a filesystem failure should abort the
current operation:

```doof
text := try! readText("config.json")
```

Handle expected cases explicitly with `case`:

```doof
case readText("optional.txt") {
  s: Success -> println(s.value)
  f: Failure -> {
    if f.error == IoError.NotFound {
      println("optional file missing")
    } else {
      panic("could not read optional.txt")
    }
  }
}
```

Boolean helpers intentionally discard the error category. Prefer `metadata` for
diagnostics, permissions, or user-facing error messages.

## Source Files

- [index.do](../index.do) defines the public functions and streaming wrappers.
- [types.do](../types.do) defines `EntryKind`, `FileInfo`, and `IoError`.
- [tests/line_streams.test.do](../tests/line_streams.test.do) covers metadata,
  line splitting, stream copying, and LF-normalized line writes.
