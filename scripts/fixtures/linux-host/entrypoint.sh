#!/bin/sh
# Installs the run's Device Key, gives the container a fresh host key, and runs
# sshd in the foreground so `docker logs` shows every session.
set -eu

if [ -z "${HEELER_AUTHORIZED_KEY:-}" ]; then
    echo "HEELER_AUTHORIZED_KEY must carry the Device Key's public line" >&2
    exit 64
fi
printf '%s\n' "$HEELER_AUTHORIZED_KEY" > /etc/ssh/heeler_authorized_keys
chmod 644 /etc/ssh/heeler_authorized_keys
ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config.heeler
