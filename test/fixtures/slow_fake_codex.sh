#!/bin/sh
set -eu
printf '%s\n' "$$" > "${CANGJIE_TEACHER_SESSION}/slow-model.pid"
printf '%s\n' 'lock-held' > "${CANGJIE_TEACHER_SESSION}/slow-model.started"
exec sleep 3600
