// Public barrel for the fs package.

export {
  EntryKind, DirEntry, IoError,
} from "./types"

export {
  readText, writeText, readBytes, writeBytes, appendText,
  exists, isFile, isDirectory, readDir,
  mkdir, remove, rename, copy,
} from "./runtime"
