#!/bin/sh
set -eu
if test -e test -o -e src/TestMain.cj; then
  printf '%s\n' 'tests_visible_before_generation' > "${CANGJIE_TEACHER_SESSION}/leak.marker"
  exit 41
fi
case "$*" in
  *"Return the input plus one."*"func addOne(value: Int64): Int64"*) ;;
  *) printf '%s\n' 'public_prompt_or_signature_missing' > "${CANGJIE_TEACHER_SESSION}/prompt.marker"; exit 42 ;;
esac
printf '%s\n' 'package cangjie_humaneval_000' '' 'public func addOne(value: Int64): Int64 { value + 1 }' > src/solution.cj
printf '%s\n' 'fake_generation_completed'
