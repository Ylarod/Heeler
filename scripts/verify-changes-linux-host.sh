#!/bin/bash
#
# Field verification of Changes against a Linux Host (#395).
#
# The merge gate reads Changes only from macOS git under POSIX sh. This script
# builds the image in scripts/fixtures/linux-host (Debian git behind OpenSSH,
# with one account whose login shell is fish and one whose login shell is
# POSIX sh), starts it on a loopback port, and runs ChangesFieldHostE2ETests
# from the Simulator against both accounts through the app's real Transport.
#
# Usage:
#   SIMULATOR_UDID=<udid> scripts/verify-changes-linux-host.sh
#
# Docker must be running. Every resource is named after HEELER_LINUX_HOST_NAME
# (default heeler-linux-host). On exit the script removes the container, the
# image (keep it with HEELER_LINUX_HOST_KEEP_IMAGE=1), the throwaway Device Key
# and the Simulator variable that points the suite at the container. Docker's
# build cache is left to Docker.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

simulator_udid="${SIMULATOR_UDID:-}"
name="${HEELER_LINUX_HOST_NAME:-heeler-linux-host}"
image="$name:local"
container="$name"
suite="ChangesFieldHostE2ETests"
test_name="Changes, file patches and an untracked directory read correctly on every configured field Host"
accounts=(heelerfish:fish heelersh:sh)

if [[ -z "$simulator_udid" ]]; then
    echo "SIMULATOR_UDID is required: the Simulator that runs the suite" >&2
    exit 2
fi
if ! docker info >/dev/null 2>&1; then
    echo "Docker is unavailable: the Linux Host verification did not run." >&2
    exit 1
fi

work_dir="$(mktemp -d)"
config_pushed=0

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    # Unset first: a stale value would point later runs at a dead container.
    if [[ "$config_pushed" == 1 ]]; then
        xcrun simctl spawn "$simulator_udid" launchctl unsetenv \
            HEELER_LINUX_HOST_E2E_CONFIG
    fi
    docker rm --force "$container" >/dev/null 2>&1
    if [[ "${HEELER_LINUX_HOST_KEEP_IMAGE:-0}" != 1 ]]; then
        docker image rm "$image" >/dev/null 2>&1
    fi
    rm -rf -- "$work_dir"
    exit "$status"
}
trap cleanup EXIT INT TERM

# A throwaway Device Key per run, in the merge gate's style: ssh-keygen makes
# it, and the suite receives only its raw seed.
ssh-keygen -q -t ed25519 -N '' -C "$name-device-key" -f "$work_dir/device_key"
device_key_seed="$(/usr/bin/python3 scripts/fixtures/openssh-ed25519-seed.py \
    "$work_dir/device_key")"

echo "==> Building $image"
if ! docker build --tag "$image" scripts/fixtures/linux-host \
    > "$work_dir/build.log" 2>&1; then
    tail -n 40 "$work_dir/build.log" >&2
    exit 1
fi
docker rm --force "$container" >/dev/null 2>&1 || true
docker run --detach --name "$container" --publish 127.0.0.1::22 \
    --env HEELER_AUTHORIZED_KEY="$(<"$work_dir/device_key.pub")" \
    "$image" >/dev/null
port="$(docker port "$container" 22/tcp \
    | sed -n 's/^127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p' | head -n 1)"
if [[ -z "$port" ]]; then
    echo "The container published no loopback port for sshd" >&2
    exit 1
fi

# sshd needs a moment to start. Prove each account can log in with the key
# before the Simulator spends a build on it.
account_json=()
for entry in "${accounts[@]}"; do
    account=${entry%%:*}
    shell=${entry#*:}
    logged_in=0
    for _ in $(seq 1 50); do
        if ssh -i "$work_dir/device_key" -p "$port" \
            -o BatchMode=yes -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$account@127.0.0.1" true </dev/null >/dev/null 2>&1; then
            logged_in=1
            break
        fi
        sleep 0.2
    done
    if [[ "$logged_in" != 1 ]]; then
        echo "$account could not log in to the container on port $port" >&2
        docker logs "$container" 2>&1 | tail -n 20 >&2
        exit 1
    fi
    account_json+=("{\"username\":\"$account\",\"loginShell\":\"$shell\"}")
done
accounts_list="$(IFS=,; echo "${account_json[*]}")"
configuration="$(printf \
    '{"host":"127.0.0.1","port":%s,"accounts":[%s],"deviceKeySeed":"%s"}' \
    "$port" "$accounts_list" "$device_key_seed" | base64)"

# The suite reads its fixture from the Simulator's launchd environment, the
# same channel the merge gate uses for its own fixtures.
xcrun simctl boot "$simulator_udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$simulator_udid" -b >/dev/null
xcrun simctl spawn "$simulator_udid" launchctl setenv \
    HEELER_LINUX_HOST_E2E_CONFIG "$configuration"
config_pushed=1

echo "==> Running $suite against $container on 127.0.0.1:$port"
# Not the merge gate: without its fixtures the suite visits only this Host.
unset HEELER_SSH_E2E_REQUIRED
test_status=0
make test-app \
    SIM_DESTINATION="platform=iOS Simulator,id=$simulator_udid" \
    TEST_FLAGS="-only-testing:HeelerTests/$suite" \
    2>&1 | tee "$work_dir/test.log" || test_status=$?

grep -F '[changes-field]' "$work_dir/test.log" || true
if [[ "$test_status" != 0 ]] \
    || ! grep -qF "Test \"$test_name\" passed" "$work_dir/test.log" \
    || ! grep -qE 'Test run with [1-9][0-9]* tests? in 1 suite passed' "$work_dir/test.log"; then
    echo "The Linux Host verification failed" >&2
    exit 1
fi
for entry in "${accounts[@]}"; do
    if ! grep -qF "[changes-field] host=linux-${entry#*:} " "$work_dir/test.log"; then
        echo "The suite never read Changes as ${entry%%:*}" >&2
        exit 1
    fi
done
echo "==> Changes, file patches and an untracked directory read correctly on" \
    "the Linux Host with fish and with POSIX sh as the login shell"
