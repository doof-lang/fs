// Public filesystem data types shared by the native runtime and consumers.

export enum EntryKind {
  File = 0,
  Directory = 1,
  Symlink = 2,
  Other = 3,
}

export class DirEntry {
  name: string
  kind: EntryKind
  size: long
  modifiedAt: long
}

export enum IoError {
  NotFound = 0,
  PermissionDenied = 1,
  AlreadyExists = 2,
  IsDirectory = 3,
  NotDirectory = 4,
  InvalidPath = 5,
  Interrupted = 6,
  Other = 7,
}