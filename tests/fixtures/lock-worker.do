import { File, FileLock, IoError, writeText } from "../../index"

import { Thread, Duration } from "std/time"

function main(args: string[]): int {
  lock := if args[1] == "shared" then FileLock.Shared else FileLock.Exclusive
  if args.length > 3 && args[2] != "hold" { try! writeText(args[3], "ready") }
  case File { path: args[0], mode: .ReadWrite, lock, waitForLock: args[2] == "wait" } {
    s: Success -> {
      if args[2] == "hold" {
        try! writeText(args[3], "locked")
        Thread.sleep(Duration.ofSeconds(30L))
      }
      try! s.value.close()
      return 0
    },
    f: Failure -> {
      if f.error == IoError.WouldBlock { return 2 }
      return 3
    }
  }
}
