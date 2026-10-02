import { EntryKind, copy, exchange, exists, metadata, mkdir, readBlob, readBlockStream, readDir, readLineStream, readText, remove, rename, writeBlob, writeBlobStream, writeLineStream, writeText } from "../index"
import { blobStreamToLineStream } from "std/stream"
import { platform, run } from "std/os"

function artifactPath(name: string): string {
  return "build/tests/" + name
}

function assertBlobContents(path: string, expected: readonly byte[]): none {
  actual := readBlob(path)!
  assert(actual.length == expected.length, "expected blob length to match")

  for index of 0..<expected.length {
    assert(actual[index] == expected[index], "expected blob byte to match")
  }
}

function collectLines(path: string, blockSize: int): string[] {
  lines: string[] := []
  stream := readLineStream(path, blockSize)!
  for line of stream {
    lines.push(line)
  }
  return lines
}

function assertCollectedLines(path: string, blockSize: int, expected: string[]): none {
  actual := collectLines(path, blockSize)
  assert(actual.length == expected.length, "expected line count to match")

  for index of 0..<expected.length {
    assert(actual[index] == expected[index], "expected collected line to match")
  }
}

function collectDecodedLines(path: string, blockSize: int): string[] {
  lines: string[] := []
  blocks := readBlockStream(path, blockSize)!
  let stream: Stream<string> = blobStreamToLineStream(blocks)
  for line of stream {
    lines.push(line)
  }
  return lines
}

function assertDecodedLines(path: string, blockSize: int, expected: string[]): none {
  actual := collectDecodedLines(path, blockSize)
  assert(actual.length == expected.length, "expected decoded line count to match")

  for index of 0..<expected.length {
    assert(actual[index] == expected[index], "expected decoded line to match")
  }
}

function assertDirContainsFile(path: string, name: string): none {
  entries := readDir(path)!
  for entry of entries {
    if entry.name == name {
      assert(entry.kind == EntryKind.File, "expected directory entry kind to be file")
      assert(entry.modifiedAt.toEpochSeconds() > 0L, "expected directory entry modified timestamp")
      return
    }
  }

  assert(false, "expected directory to contain file")
}

export function testAll() {
  if !exists("build") { mkdir("build")! }
  if !exists("build/tests") { mkdir("build/tests")! }
  emptyPath := artifactPath(".line-streams.empty.txt")
  mixedPath := artifactPath(".line-streams.mixed.txt")
  sourcePath := artifactPath(".line-streams.source.txt")
  outputPath := artifactPath(".line-streams.output.txt")
  blobSourcePath := artifactPath(".line-streams.source.bin")
  blobOutputPath := artifactPath(".line-streams.output.bin")
  unterminatedPath := artifactPath(".line-streams.unterminated.txt")
  trailingCrPath := artifactPath(".line-streams.trailing-cr.txt")
  renameSourcePath := artifactPath(".line-streams.rename-source.txt")
  renameDestinationPath := artifactPath(".line-streams.rename-destination.txt")
  exchangeFirstPath := artifactPath(".line-streams.exchange-first.txt")
  exchangeSecondPath := artifactPath(".line-streams.exchange-second.txt")
  exchangeFirstDirectory := artifactPath(".line-streams.exchange-first")
  exchangeSecondDirectory := artifactPath(".line-streams.exchange-second")
  executableSourcePath := artifactPath(".line-streams.executable-source")
  executableCopyPath := artifactPath(".line-streams.executable-copy")

  writeText(emptyPath, "")!
  emptyMetadata := metadata(emptyPath)!
  assert(emptyMetadata.name == ".line-streams.empty.txt", "expected metadata name")
  assert(emptyMetadata.kind == EntryKind.File, "expected metadata kind to be file")
  assert(emptyMetadata.size == 0L, "expected empty file size")
  assert(emptyMetadata.modifiedAt.toEpochSeconds() > 0L, "expected modified timestamp")
  assertDirContainsFile("build/tests", ".line-streams.empty.txt")

  writeText(mixedPath, "alpha\r\n\rbeta\n")!
  assert(readText(mixedPath)! == "alpha\r\n\rbeta\n", "expected writeText to preserve newline bytes")
  writeText(sourcePath, "alpha\r\n\rbeta\n")!
  writeBlob(blobSourcePath, [0, 1, 2, 3, 254, 255])!
  writeText(unterminatedPath, "alpha\r\nbeta")!
  writeText(trailingCrPath, "alpha\r")!
  writeText(renameSourcePath, "replacement")!
  writeText(renameDestinationPath, "original")!
  writeText(exchangeFirstPath, "first")!
  writeText(exchangeSecondPath, "second")!

  rename(renameSourcePath, renameDestinationPath)!
  assert(!exists(renameSourcePath), "expected rename source to be removed")
  assert(readText(renameDestinationPath)! == "replacement", "expected rename to replace destination")

  exchangeResult := exchange(exchangeFirstPath, exchangeSecondPath)
  if platform() == "darwin" || platform() == "linux" {
    exchangeResult!
    assert(readText(exchangeFirstPath)! == "second", "expected exchange first path to contain second file")
    assert(readText(exchangeSecondPath)! == "first", "expected exchange second path to contain first file")

    mkdir(exchangeFirstDirectory)!
    mkdir(exchangeSecondDirectory)!
    writeText(exchangeFirstDirectory + "/value", "directory-first")!
    writeText(exchangeSecondDirectory + "/value", "directory-second")!
    exchange(exchangeFirstDirectory, exchangeSecondDirectory)!
    assert(readText(exchangeFirstDirectory + "/value")! == "directory-second", "expected non-empty directories to exchange")
    assert(readText(exchangeSecondDirectory + "/value")! == "directory-first", "expected exchanged directory contents")

    missingExchange := exchange(artifactPath(".missing"), exchangeFirstPath)
    case missingExchange {
      _: Failure -> { },
      _: Success -> assert(false, "expected exchange with a missing path to fail"),
    }

    writeText(executableSourcePath, "executable")!
    assert((run("/bin/chmod", ["0555", executableSourcePath])!).exitCode == 0, "expected chmod fixture setup")
    copy(executableSourcePath, executableCopyPath)!
    assert((run("/bin/test", ["-x", executableCopyPath])!).exitCode == 0, "expected copy to preserve executable mode")
  }

  assertCollectedLines(emptyPath, 2, [])
  assertCollectedLines(mixedPath, 2, ["alpha", "", "beta"])
  assertDecodedLines(mixedPath, 2, ["alpha", "", "beta"])
  assertDecodedLines(mixedPath, 1, ["alpha", "", "beta"])
  assertCollectedLines(unterminatedPath, 2, ["alpha", "beta"])
  assertDecodedLines(unterminatedPath, 2, ["alpha", "beta"])
  assertCollectedLines(trailingCrPath, 1, ["alpha"])
  assertDecodedLines(trailingCrPath, 1, ["alpha"])

  sourceLines := readLineStream(sourcePath, 2)!
  writeLineStream(outputPath, sourceLines)!
  assert(readText(outputPath)! == "alpha\n\nbeta\n", "expected writeLineStream to normalize endings to LF")

  sourceBlob := readBlockStream(blobSourcePath, 2)!
  writeBlobStream(blobOutputPath, sourceBlob)!
  assertBlobContents(blobOutputPath, [0, 1, 2, 3, 254, 255])

  remove(emptyPath)!
  remove(mixedPath)!
  remove(sourcePath)!
  remove(outputPath)!
  remove(blobSourcePath)!
  remove(blobOutputPath)!
  remove(unterminatedPath)!
  remove(trailingCrPath)!
  remove(renameDestinationPath)!
  remove(exchangeFirstPath)!
  remove(exchangeSecondPath)!
  if platform() == "darwin" || platform() == "linux" {
    remove(exchangeFirstDirectory + "/value")!
    remove(exchangeSecondDirectory + "/value")!
    remove(exchangeFirstDirectory)!
    remove(exchangeSecondDirectory)!
    remove(executableSourcePath)!
    remove(executableCopyPath)!
  }
}
