import { exists, readBlob, readBlockStream, readLineStream, readText, remove, writeBlob, writeBlobStream, writeLineStream, writeText } from "../index"
import { blobStreamToLineStream } from "std/stream"

function artifactPath(name: string): string {
  return "build/tests/" + name
}

function assertBlobContents(path: string, expected: readonly byte[]): void {
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

function assertCollectedLines(path: string, blockSize: int, expected: string[]): void {
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

function assertDecodedLines(path: string, blockSize: int, expected: string[]): void {
  actual := collectDecodedLines(path, blockSize)
  assert(actual.length == expected.length, "expected decoded line count to match")

  for index of 0..<expected.length {
    assert(actual[index] == expected[index], "expected decoded line to match")
  }
}

export function testAll() {
  emptyPath := artifactPath(".line-streams.empty.txt")
  mixedPath := artifactPath(".line-streams.mixed.txt")
  sourcePath := artifactPath(".line-streams.source.txt")
  outputPath := artifactPath(".line-streams.output.txt")
  blobSourcePath := artifactPath(".line-streams.source.bin")
  blobOutputPath := artifactPath(".line-streams.output.bin")
  unterminatedPath := artifactPath(".line-streams.unterminated.txt")
  trailingCrPath := artifactPath(".line-streams.trailing-cr.txt")

  try! writeText(emptyPath, "")
  try! writeText(mixedPath, "alpha\r\n\rbeta\n")
  try! writeText(sourcePath, "alpha\r\n\rbeta\n")
  try! writeBlob(blobSourcePath, [0, 1, 2, 3, 254, 255])
  try! writeText(unterminatedPath, "alpha\r\nbeta")
  try! writeText(trailingCrPath, "alpha\r")

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
}