import { File, exists, remove, writeBlob } from "../index"
import { Exec, ExecOptions, env, platform, run } from "std/os"
import { Duration, Thread } from "std/time"

export function testFileCrossProcessLocks(): none {
  // Resolve the source fixture independently of the generated test runner cwd.
  let root = env("DOOF_STDLIB_ROOT") ?? "."
  let depth = 0
  while !exists(root + "/fs/tests/fixtures/lock-worker.do") && depth < 8 {
    root += "/.."
    depth += 1
  }
  assert(exists(root + "/fs/tests/fixtures/lock-worker.do"), "must locate lock fixture")
  output := root + "/fs/build/lock-worker"
  built := try! run("doof", ["build", root + "/fs/tests/fixtures/lock-worker.do", "-o", output], ExecOptions { timeout: Duration.ofSeconds(120L) })
  assert(built.exitCode == 0, "lock worker must build")
  worker := output + (if platform() == "windows" then "/std-fs.exe" else "/std-fs")
  path := root + "/fs/build/process-lock.bin"
  ready := root + "/fs/build/process-lock.ready"
  if exists(ready) { try! remove(ready) }
  try! writeBlob(path, [])
  shared := try! File { path, lock: .Shared }
  options := ExecOptions { timeout: Duration.ofSeconds(10L) }
  assert((try! run(worker, [path, "shared", "try"], options)).exitCode == 0, "shared locks coexist across processes")
  assert((try! run(worker, [path, "exclusive", "try"], options)).exitCode == 2, "exclusive child must contend")
  try! shared.close()
  exclusive := try! File { path, mode: .ReadWrite, lock: .Exclusive }
  assert((try! run(worker, [path, "shared", "try"], options)).exitCode == 2, "shared child must contend")
  assert((try! run(worker, [path, "exclusive", "try"], options)).exitCode == 2, "exclusive child must contend")
  child := try! Exec.spawn(worker, [path, "exclusive", "wait", ready], options)
  let attempts = 0
  while !exists(ready) && attempts < 500 {
    Thread.sleep(Duration.ofMillis(10L))
    attempts += 1
  }
  assert(exists(ready), "child must reach lock acquisition")
  Thread.sleep(Duration.ofMillis(100L))
  assert(child.isRunning(), "blocking child must wait while parent holds lock")
  try! exclusive.close()
  assert((try! child.wait()) == 0, "child must acquire after release")
  try! remove(ready)
  holder := try! Exec.spawn(worker, [path, "exclusive", "hold", ready], options)
  attempts = 0
  while !exists(ready) && attempts < 500 {
    Thread.sleep(Duration.ofMillis(10L))
    attempts += 1
  }
  assert(exists(ready), "holder must acquire before termination")
  assert((try! run(worker, [path, "shared", "try"], options)).exitCode == 2, "holder owns its lock")
  try! holder.terminate()
  exitCode := try! holder.wait()
  assert(exitCode != 0, "holder must terminate before normal completion")
  assert((try! run(worker, [path, "exclusive", "try"], options)).exitCode == 0, "process exit must release lock")
  try! remove(ready)
  try! remove(path)
}
