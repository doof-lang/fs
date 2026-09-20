#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
module_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
stdlib_dir=$(CDPATH= cd -- "$module_dir/.." && pwd)
worker_output="$module_dir/build/lock-worker"

export DOOF_STDLIB_ROOT="${DOOF_STDLIB_ROOT:-$stdlib_dir}"

doof build "$module_dir/tests/fixtures/lock-worker.do" -o "$worker_output"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) worker="$worker_output/std-fs.exe" ;;
  *) worker="$worker_output/std-fs" ;;
esac

doof run "$module_dir/tests/file_process.integration.do" -- "$worker"
