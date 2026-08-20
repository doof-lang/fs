import { EntryKind, copy, exchange, exists, metadata, mkdir, readBlob, readBlockStream, readDir, readLineStream, readText, remove, rename, writeBlob, writeBlobStream, writeLineStream, writeText } from "../index"
import { blobStreamToLineStream } from "std/stream"
import { platform, run } from "std/os"

function artifactPath(name: string): string {
  return "build/tests/" + name
}

function assertBlobContents(path: string, expected: readonly byte[]): none {
  actual := try! readBlob(path)
  assert(actual.length == expected.length, "expected blob length to match")

  for index of 0..<expected.length {
    assert(actual[index] == expected[index], "expected blob byte to match")
  }
}

function collectLines(path: string, blockSize: int): string[] {
  lines: string[] := []
  stream := try! readLineStream(path, blockSize)
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
  blocks := try! readBlockStream(path, blockSize)
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
  entries := try! readDir(path)
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
  if !exists("build") { try! mkdir("build") }
  if !exists("build/tests") { try! mkdir("build/tests") }
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

  try! writeText(emptyPath, "")
  emptyMetadata := try! metadata(emptyPath)
  assert(emptyMetadata.name == ".line-streams.empty.txt", "expected metadata name")
  assert(emptyMetadata.kind == EntryKind.File, "expected metadata kind to be file")
  assert(emptyMetadata.size == 0L, "expected empty file size")
  assert(emptyMetadata.modifiedAt.toEpochSeconds() > 0L, "expected modified timestamp")
  assertDirContainsFile("build/tests", ".line-streams.empty.txt")

  try! writeText(mixedPath, "alpha\r\n\rbeta\n")
  assert(try! readText(mixedPath) == "alpha\r\n\rbeta\n", "expected writeText to preserve newline bytes")
  try! writeText(sourcePath, "alpha\r\n\rbeta\n")
  try! writeBlob(blobSourcePath, [0, 1, 2, 3, 254, 255])
  try! writeText(unterminatedPath, "alpha\r\nbeta")
  try! writeText(trailingCrPath, "alpha\r")
  try! writeText(renameSourcePath, "replacement")
  try! writeText(renameDestinationPath, "original")
  try! writeText(exchangeFirstPath, "first")
  try! writeText(exchangeSecondPath, "second")

  try! rename(renameSourcePath, renameDestinationPath)
  assert(!exists(renameSourcePath), "expected rename source to be removed")
  assert(try! readText(renameDestinationPath) == "replacement", "expected rename to replace destination")

  exchangeResult := exchange(exchangeFirstPath, exchangeSecondPath)
  if platform() == "darwin" {
    try! exchangeResult
    assert(try! readText(exchangeFirstPath) == "second", "expected exchange first path to contain second file")
    assert(try! readText(exchangeSecondPath) == "first", "expected exchange second path to contain first file")

    try! mkdir(exchangeFirstDirectory)
    try! mkdir(exchangeSecondDirectory)
    try! writeText(exchangeFirstDirectory + "/value", "directory-first")
    try! writeText(exchangeSecondDirectory + "/value", "directory-second")
    try! exchange(exchangeFirstDirectory, exchangeSecondDirectory)
    assert(try! readText(exchangeFirstDirectory + "/value") == "directory-second", "expected non-empty directories to exchange")
    assert(try! readText(exchangeSecondDirectory + "/value") == "directory-first", "expected exchanged directory contents")

    missingExchange := exchange(artifactPath(".missing"), exchangeFirstPath)
    case missingExchange {
      _: Failure -> { },
      _: Success -> assert(false, "expected exchange with a missing path to fail"),
    }

    try! writeText(executableSourcePath, "executable")
    assert((try! run("/bin/chmod", ["0555", executableSourcePath])).exitCode == 0, "expected chmod fixture setup")
    try! copy(executableSourcePath, executableCopyPath)
    assert((try! run("/bin/test", ["-x", executableCopyPath])).exitCode == 0, "expected copy to preserve executable mode")
  }

  assertCollectedLines(emptyPath, 2, [])
  assertCollectedLines(mixedPath, 2, ["alpha", "", "beta"])
  assertDecodedLines(mixedPath, 2, ["alpha", "", "beta"])
  assertDecodedLines(mixedPath, 1, ["alpha", "", "beta"])
  assertCollectedLines(unterminatedPath, 2, ["alpha", "beta"])
  assertDecodedLines(unterminatedPath, 2, ["alpha", "beta"])
  assertCollectedLines(trailingCrPath, 1, ["alpha"])
  assertDecodedLines(trailingCrPath, 1, ["alpha"])

  sourceLines := try! readLineStream(sourcePath, 2)
  try! writeLineStream(outputPath, sourceLines)
  assert(try! readText(outputPath) == "alpha\n\nbeta\n", "expected writeLineStream to normalize endings to LF")

  sourceBlob := try! readBlockStream(blobSourcePath, 2)
  try! writeBlobStream(blobOutputPath, sourceBlob)
  assertBlobContents(blobOutputPath, [0, 1, 2, 3, 254, 255])

  try! remove(emptyPath)
  try! remove(mixedPath)
  try! remove(sourcePath)
  try! remove(outputPath)
  try! remove(blobSourcePath)
  try! remove(blobOutputPath)
  try! remove(unterminatedPath)
  try! remove(trailingCrPath)
  try! remove(renameDestinationPath)
  try! remove(exchangeFirstPath)
  try! remove(exchangeSecondPath)
  if platform() == "darwin" {
    try! remove(exchangeFirstDirectory + "/value")
    try! remove(exchangeSecondDirectory + "/value")
    try! remove(exchangeFirstDirectory)
    try! remove(exchangeSecondDirectory)
    try! remove(executableSourcePath)
    try! remove(executableCopyPath)
  }
}
