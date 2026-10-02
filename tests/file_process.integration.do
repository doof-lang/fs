import { File, exists, remove, writeBlob } from "../index"
import { Exec, ExecOptions, env, platform, run } from "std/os"
import { Duration, Thread } from "std/time"

function main(args: string[]): int {
  assert(args.length == 1, "expected the lock worker executable path")
  worker := args[0]
  // Resolve the checkout independently of the integration runner cwd.
  let root = env("DOOF_STDLIB_ROOT") ?? "."
  let depth = 0
  while !exists(root + "/fs/tests/fixtures/lock-worker.do") && depth < 8 {
    root += "/.."
    depth += 1
  }
  assert(exists(root + "/fs/tests/fixtures/lock-worker.do"), "must locate lock fixture")
  path := root + "/fs/build/process-lock.bin"
  ready := root + "/fs/build/process-lock.ready"
  if exists(ready) { remove(ready)! }
  writeBlob(path, [])!
  shared := File { path, lock: .Shared }!
  options := ExecOptions { timeout: Duration.ofSeconds(10L) }
  assert((run(worker, [path, "shared", "try"], options)!).exitCode == 0, "shared locks coexist across processes")
  assert((run(worker, [path, "exclusive", "try"], options)!).exitCode == 2, "exclusive child must contend")
  shared.close()!
  exclusive := File { path, mode: .ReadWrite, lock: .Exclusive }!
  assert((run(worker, [path, "shared", "try"], options)!).exitCode == 2, "shared child must contend")
  assert((run(worker, [path, "exclusive", "try"], options)!).exitCode == 2, "exclusive child must contend")
  child := Exec.spawn(worker, [path, "exclusive", "wait", ready], options)!
  let attempts = 0
  while !exists(ready) && attempts < 500 {
    Thread.sleep(Duration.ofMillis(10L))
    attempts += 1
  }
  assert(exists(ready), "child must reach lock acquisition")
  Thread.sleep(Duration.ofMillis(100L))
  assert(child.isRunning(), "blocking child must wait while parent holds lock")
  exclusive.close()!
  assert((child.wait()!) == 0, "child must acquire after release")
  remove(ready)!
  holder := Exec.spawn(worker, [path, "exclusive", "hold", ready], options)!
  attempts = 0
  while !exists(ready) && attempts < 500 {
    Thread.sleep(Duration.ofMillis(10L))
    attempts += 1
  }
  assert(exists(ready), "holder must acquire before termination")
  assert((run(worker, [path, "shared", "try"], options)!).exitCode == 2, "holder owns its lock")
  holder.terminate()!
  exitCode := holder.wait()!
  assert(exitCode != 0, "holder must terminate before normal completion")
  assert((run(worker, [path, "exclusive", "try"], options)!).exitCode == 0, "process exit must release lock")
  remove(ready)!
  remove(path)!
  return 0
}
