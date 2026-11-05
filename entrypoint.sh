#!/bin/sh
# TimeTagger Railway wrapper entrypoint (Debian /bin/sh; python3 +
# bcrypt are bundled in the upstream image, no curl/wget).
#
# What it does, in order:
# - DATA: /data is the single Railway volume; the whole TimeTagger
#   datadir (user databases under /data/users) lives there.
# - PORT: Railway injects PORT at runtime. Upstream binds
#   TIMETAGGER_BIND (verified in timetagger/_config.py +
#   __main__.py). Export TIMETAGGER_BIND=0.0.0.0:$PORT on every boot.
# - PATH PREFIX: TIMETAGGER_PATH_PREFIX=/ serves the app at the
#   root, TIMETAGGER_APP_REDIRECT=true sends / straight to the app,
#   and /status is the unauthenticated health endpoint.
# - ADMIN: upstream login is username + bcrypt hash via
#   TIMETAGGER_CREDENTIALS ("user:hash,..."). The template supplies
#   ADMIN_PASSWORD (generated ${{secret(16)}}); the wrapper hashes
#   it with the image's bundled bcrypt on every boot and hands the
#   hash to the server. A fresh salt each boot is fine: login
#   verifies the password against the hash, and the hash is never
#   stored. If TIMETAGGER_CREDENTIALS is set directly (multi-user),
#   it wins and ADMIN_PASSWORD is ignored. If neither is set, fail
#   loud: a server with no credentials can never be logged into
#   from behind the Railway proxy.
# - STEADY STATE: exec the server in the foreground, exactly as
#   upstream does (python -m timetagger).

DATA_DIR="/data"

mkdir -p "$DATA_DIR"

# Defensive writability check. As root on Railway's root-owned volume
# this passes; fail loud if it ever does not, instead of
# crash-looping silently.
if [ ! -w "$DATA_DIR" ] || [ ! -x "$DATA_DIR" ]; then
  echo "TimeTagger: ERROR $DATA_DIR is not writable/executable for the current user; refusing to start."
  exit 1
fi

PORT_VALUE="${PORT:-8080}"
export TIMETAGGER_BIND="0.0.0.0:${PORT_VALUE}"
export TIMETAGGER_DATADIR="$DATA_DIR"
export TIMETAGGER_PATH_PREFIX="/"
export TIMETAGGER_APP_REDIRECT=true
export TIMETAGGER_LOG_LEVEL="${TIMETAGGER_LOG_LEVEL:-info}"

if [ -z "${TIMETAGGER_CREDENTIALS:-}" ]; then
  if [ -z "${ADMIN_PASSWORD:-}" ]; then
    echo "TimeTagger: ERROR neither TIMETAGGER_CREDENTIALS nor ADMIN_PASSWORD is set; no one could log in. Set ADMIN_PASSWORD and redeploy."
    exit 1
  fi
  # bcrypt hashes contain "$2b$..." — the expansion result of $HASH is
  # inserted literally and never re-expanded, so the $ signs survive.
  HASH=$(ADMIN_PASSWORD="$ADMIN_PASSWORD" python -c 'import bcrypt, os; print(bcrypt.hashpw(os.environ["ADMIN_PASSWORD"].encode(), bcrypt.gensalt()).decode())')
  export TIMETAGGER_CREDENTIALS="admin:${HASH}"
  unset HASH
  unset ADMIN_PASSWORD
fi

echo "TimeTagger: binding 0.0.0.0:${PORT_VALUE}, data ${DATA_DIR} (volume), app at /"
exec python -m timetagger
