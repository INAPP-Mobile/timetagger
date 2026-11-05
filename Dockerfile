# TimeTagger on Railway — wrapper around the pinned upstream image.
#
# Why a wrapper at all (house style: bake constants, keep the deploy
# form zero-field, and survive Railway's root-owned volumes):
# - PORT: TimeTagger binds TIMETAGGER_BIND (default 127.0.0.1:8080).
#   entrypoint.sh exports TIMETAGGER_BIND=0.0.0.0:$PORT on every boot
#   (verified in upstream timetagger/_config.py + __main__.py:
#   asgineer.run(..., config.bind, ...) — bind is the host:port the
#   server listens on). Railway injects PORT at runtime.
# - PATH PREFIX: upstream serves at /timetagger/ by default and the
#   root path only 307-redirects there; a Railway healthcheck needs a
#   plain 200. The wrapper sets TIMETAGGER_PATH_PREFIX=/ so the app
#   serves at the root, TIMETAGGER_APP_REDIRECT=true so / goes
#   straight to the app, and the healthcheck is the upstream status
#   endpoint /status (returns 200 "ok" without auth, verified in
#   __main__.py main_handler). The client builds API URLs from
#   location.pathname (timetagger/app/tools.py build_api_url), so
#   serving at / needs no frontend patch.
# - USER root: the stock image already runs as root
#   (python:3.13-slim-bookworm, no USER directive), so the
#   root-owned Railway volume is writable with no change. The
#   wrapper states USER root explicitly so a future upstream
#   non-root switch cannot silently break the volume.
# - DATA: a single Railway volume at /data holds the whole
#   TimeTagger datadir (user databases under /data/users).
#   TIMETAGGER_DATADIR=/data is baked in. Railway allows one
#   volume per service, so everything lives under /data.
# - ADMIN: upstream login is username + bcrypt-hashed password via
#   TIMETAGGER_CREDENTIALS ("user:hash,...", verified in
#   timetagger/_config.py + __main__.py get_webtoken_usernamepassword).
#   Railway cannot compute a bcrypt hash, so the wrapper hashes the
#   template's generated ADMIN_PASSWORD with the bcrypt library
#   bundled in the image on every boot and hands the hash to the
#   server. A fresh salt each boot is fine: login verifies the
#   password against the hash, and the hash is never stored anywhere.
#   Changing ADMIN_PASSWORD later changes the login password on the
#   next deploy (unlike OpenList, where the seeded password sticks).
#   If TIMETAGGER_CREDENTIALS is set directly (multi-user), the
#   wrapper respects it and ADMIN_PASSWORD is ignored.
# - No Docker HEALTHCHECK: rely on Railway's external
#   healthcheckPath (/status). The slim base image ships no curl.
#
# Upstream: TimeTagger v26.1.3 (GPL-3.0), image pinned by manifest
# digest, verified 2026-11-05 via the GitHub Packages API
# (multi-arch manifest-list digest below). NOTE: the FROM uses the
# digest WITHOUT a tag — Railpack 0.43.0 fails to detect a Dockerfile
# whose FROM carries both a tag and a digest (redeploys die in the
# plan phase with "could not determine how to build"); the
# digest-only form builds under both the Dockerfile builder and
# Railpack (verified 2026-11-05 — FileGator's digest-only FROM is
# the precedent).

FROM ghcr.io/almarklein/timetagger@sha256:04797c616a25760ee94b352273535a516881ca820e507aee9abf7a63e5768502

USER root

COPY entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

# Baked constants (see header): the datadir is the Railway volume.
ENV TIMETAGGER_DATADIR=/data

# Documentation only: Railway routes to $PORT at runtime (see
# entrypoint.sh); 8080 is the upstream default the image would use
# without the wrapper's TIMETAGGER_BIND mapping.
EXPOSE 8080

CMD ["/railway-entrypoint.sh"]
