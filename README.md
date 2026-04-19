# fs

POSIX-oriented filesystem I/O. Provides one-shot functions for reading and writing entire files as text or binary, streaming APIs for large files, and directory utilities — all returning `Result` types so errors are handled explicitly.

## Usage

```doof
import { readText, writeText, readLineStream, exists } from "fs"

// One-shot read
content := try readText("/etc/hostname")

// Stream lines lazily
stream := try readLineStream("data.csv")
for line of stream {
  println(line)
}

// Check before writing
if !exists("output/") {
  try mkdir("output/")
}
try writeText("output/result.txt", content)
```

## Exports

### Types

#### `EntryKind`

Classifies a directory entry returned by `readDir`.

| Member | Value | Description |
|--------|-------|-------------|
| `File` | `0` | Regular file |
| `Directory` | `1` | Directory |
| `Symlink` | `2` | Symbolic link |
| `Other` | `3` | Device node, pipe, socket, etc. |

#### `DirEntry`

Metadata for a single entry returned by `readDir`.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Entry name (not a full path) |
| `kind` | `EntryKind` | Entry type |
| `size` | `long` | File size in bytes |
| `modifiedAt` | `long` | Last-modified time as a Unix timestamp (seconds) |

#### `IoError`

Error cases returned by filesystem operations.

| Member | Value | Description |
|--------|-------|-------------|
| `NotFound` | `0` | Path does not exist |
| `PermissionDenied` | `1` | Insufficient permissions |
| `AlreadyExists` | `2` | Target already exists |
| `IsDirectory` | `3` | Expected a file but found a directory |
| `NotDirectory` | `4` | Expected a directory but found a file |
| `InvalidPath` | `5` | Malformed or unsupported path |
| `Interrupted` | `6` | Operation interrupted by a signal |
| `Other` | `7` | Any other OS error |

---

### One-shot functions

#### `readText(path: string): Result<string, IoError>`

Read an entire file as a UTF-8 string.

#### `writeText(path: string, content: string): Result<void, IoError>`

Write (or overwrite) a file with the given string content.

#### `readBlob(path: string): Result<readonly byte[], IoError>`

Read an entire file as a raw byte array.

#### `writeBlob(path: string, data: readonly byte[]): Result<void, IoError>`

Write (or overwrite) a file with the given bytes.

#### `appendText(path: string, content: string): Result<void, IoError>`

Append a string to an existing file (creates the file if absent).

#### `appendBlob(path: string, data: readonly byte[]): Result<void, IoError>`

Append bytes to an existing file (creates the file if absent).

---

### Streaming functions

Streaming reads process the file in chunks, avoiding loading the entire file into memory. The optional `blockSize` parameter (default `65536`) controls the internal read-chunk size in bytes.

#### `readBlockStream(path: string, blockSize?: int): Result<Stream<readonly byte[]>, IoError>`

Open a file for streaming reads, yielding raw byte-array chunks.

#### `readBlobStream(path: string, blockSize?: int): Result<Stream<readonly byte[]>, IoError>`

Alias for `readBlockStream`.

#### `readLineStream(path: string, blockSize?: int): Result<Stream<string>, IoError>`

Open a file for streaming reads, yielding one decoded UTF-8 line per iteration. Handles `\n`, `\r`, and `\r\n` line endings.

```doof
stream := try readLineStream("large.log")
for line of stream {
  println(line)
}
```

#### `writeBlobStream(path: string, chunks: Stream<readonly byte[]>): Result<void, IoError>`

Write all chunks from a `Stream<readonly byte[]>` to a file sequentially.

#### `writeLineStream(path: string, lines: Stream<string>): Result<void, IoError>`

Write all strings from a `Stream<string>` to a file, appending a newline after each.

---

### Directory and metadata functions

#### `exists(path: string): bool`

Return `true` if the path exists (file, directory, or symlink).

#### `isFile(path: string): bool`

Return `true` if the path is a regular file.

#### `isDirectory(path: string): bool`

Return `true` if the path is a directory.

#### `readDir(path: string): Result<DirEntry[], IoError>`

Return the entries of a directory. Does not recurse.

#### `mkdir(path: string): Result<void, IoError>`

Create a directory. Fails if it already exists.

#### `remove(path: string): Result<void, IoError>`

Delete a file or empty directory.

#### `rename(sourcePath: string, destPath: string): Result<void, IoError>`

Move or rename a file or directory.

#### `copy(sourcePath: string, destPath: string): Result<void, IoError>`

Copy a file to a new path.
