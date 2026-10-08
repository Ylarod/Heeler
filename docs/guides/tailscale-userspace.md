# Tailscale on macOS Without a Network Extension or TUN

This guide runs the Homebrew `tailscaled` binary with `--tun=userspace-networking` and forwards one tailnet TCP port to the Mac's ordinary SSH server. Heeler then reaches herdr over that SSH connection. The Mac daemon creates no TUN interface or macOS VPN configuration in this mode, and Heeler uses its own in-app Tailscale node on iOS.

Use a Heeler build that includes [PR #426](https://github.com/ZingerLittleBee/Heeler/pull/426). This is a manual CLI setup for users who want to manage a daemon; for the standard desktop setup, use [Connect Through Tailscale](tailscale.md).

```text
Heeler's Tailscale node
  → Mac's userspace Tailscale node, TCP 22
  → Tailscale Serve raw TCP forwarding
  → 127.0.0.1:22, macOS Remote Login
  → herdr over SSH
```

## 1. Prepare and verify the local SSH server

Complete [Prepare the Host](overlay-networks.md#prepare-the-host). Before adding the overlay, check that SSH listens on IPv4 loopback:

```sh
nc -vz 127.0.0.1 22
```

Expect a successful TCP connection. If you also have SSH credentials usable from the Mac, verify a full local login:

```sh
ssh -p 22 "$(id -un)@127.0.0.1"
```

Use the intended SSH account instead of `$(id -un)` if it differs from your current account. Check the server fingerprint before accepting it, then exit after confirming access. A connection refusal means Remote Login or its listener needs attention. An authentication failure can instead mean the Mac lacks suitable credentials: authorizing Heeler's public key does not give this Mac the phone's private key. In that case, verify Heeler's authentication in step 6; keep the private key on the phone and retain your SSH authentication policy.

## 2. Install the CLI binaries

With [Homebrew](https://brew.sh/) installed, install the formula:

```sh
brew install --formula tailscale
```

The [upstream macOS CLI guide](https://github.com/tailscale/tailscale/wiki/Tailscaled-on-macOS) confirms this formula. Its default service instructions use the normal macOS `utun` path. For this guide, start the daemon explicitly with the userspace flag below; `sudo brew services start tailscale` does not select userspace mode.

## 3. Start a private userspace daemon

In **Terminal A**, run:

```sh
TS_BIN="$(brew --prefix tailscale)/bin"
TS_STATE_DIR="$HOME/.local/share/heeler-tailscale"
umask 077
mkdir -p "$TS_STATE_DIR"
chmod 700 "$TS_STATE_DIR"
"$TS_BIN/tailscaled" \
  --tun=userspace-networking \
  --statedir="$TS_STATE_DIR" \
  --socket="$TS_STATE_DIR/tailscaled.socket"
```

Leave this terminal running. The state directory stores this node's identity and settings; keep it private and reuse it on subsequent starts. Do not point a second daemon at the same directory or socket. The explicit Homebrew binary path also avoids accidentally calling a CLI wrapper belonging to the GUI app.

The [userspace networking documentation](https://tailscale.com/docs/concepts/userspace-networking) defines the `--tun=userspace-networking` switch. This mode does not install tailnet routes for other Mac applications. The incoming SSH path here is supplied explicitly by Serve; a normal `ssh` command on this Mac does not automatically gain access to other tailnet peers.

## 4. Sign in through the private socket

In **Terminal B**, define the same paths, then sign in:

```sh
TS_BIN="$(brew --prefix tailscale)/bin"
TS_STATE_DIR="$HOME/.local/share/heeler-tailscale"
"$TS_BIN/tailscale" --socket="$TS_STATE_DIR/tailscaled.socket" up \
  --hostname=heeler-mac-userspace
"$TS_BIN/tailscale" --socket="$TS_STATE_DIR/tailscaled.socket" status
"$TS_BIN/tailscale" --socket="$TS_STATE_DIR/tailscaled.socket" ip -4
```

Open the login URL printed by `up` and join the tailnet you will use in Heeler. Complete any required administrator approval, then record the IPv4 address reported by `ip -4`. This daemon is its own tailnet device; an existing GUI app can have a different node name and address. Keep using `--socket` in every command for this setup so you control the intended daemon.

Use ordinary SSH authentication through macOS Remote Login. Do not enable Tailscale SSH with `--ssh` for this recipe: port 22 will carry the local SSH server through Serve.

## 5. Forward tailnet port 22 to Remote Login

In Terminal B, configure the raw TCP forwarder and inspect it:

```sh
"$TS_BIN/tailscale" --socket="$TS_STATE_DIR/tailscaled.socket" serve \
  --bg --tcp=22 tcp://127.0.0.1:22
"$TS_BIN/tailscale" --socket="$TS_STATE_DIR/tailscaled.socket" serve status
```

Check that the output shows the node's tailnet TCP port `22` forwarding to `127.0.0.1:22`. This is a raw TCP listener inside the tailnet, with SSH still authenticating the user and server. Tailnet policy must permit Heeler's node to reach this node on TCP 22. The [Serve TCP reference](https://tailscale.com/docs/reference/tailscale-cli/serve) and [SSH forwarding example](https://tailscale.com/docs/reference/examples/serve#bind-local-services-to-your-tailnet) document this forwarding mode.

The tailnet listener is inside the userspace daemon, so using port 22 here does not conflict with macOS SSH listening on its own port 22. The loopback target does not change Remote Login's existing LAN exposure or firewall rules. Serve shares this endpoint with the tailnet; this setup does not use Funnel or publish it to the internet.

## 6. Connect Heeler and verify the complete path

Follow [Join the same tailnet from Heeler](tailscale.md#3-join-the-same-tailnet-from-heeler), then [Connect from Heeler](overlay-networks.md#connect-from-heeler). Choose this Overlay Network in the Host form, select `heeler-mac-userspace` through **Choose from Tailnet…**, or enter the exact IPv4 address from step 4. Use Port `22`, the Mac's local account, and the SSH authentication method from step 1. Leave Jump Host blank.

Complete [Verify the connection](overlay-networks.md#verify-the-connection). A successful SSH login to `127.0.0.1` proves only the local server; a successful Heeler connection proves the userspace node, Serve forwarding, SSH authentication, and herdr path together. For another independent check, an already connected tailnet device with normal system networking can run `ssh -p 22 your-mac-user@your-mac-tailscale-ip`, replacing both placeholders.

## Stop forwarding or stop the daemon

To remove only this Serve listener, run in Terminal B:

```sh
"$TS_BIN/tailscale" --socket="$TS_STATE_DIR/tailscaled.socket" serve \
  --bg --tcp=22 off
"$TS_BIN/tailscale" --socket="$TS_STATE_DIR/tailscaled.socket" serve status
```

To stop the daemon, press **Control-C in Terminal A**. Keep the private state directory to retain this node's identity. Restart with the same command in step 3 and inspect `status` and `serve status` through the same socket before relying on remote access again.

`serve --bg` retains the forwarding configuration after its CLI command exits; it does not put `tailscaled` in the background or install a login or boot service. Closing Terminal A, logging out, rebooting, or sleeping the Mac can interrupt access. An unattended deployment needs a separately managed daemon with the same userspace flag, private state directory, socket, and appropriate startup lifecycle. This guide does not install that service; use the standard macOS app if managing it is unnecessary for your setup.

## Troubleshooting

| Symptom | Check |
|---|---|
| The CLI cannot reach `tailscaled` | Terminal A is still running and Terminal B uses exactly the same socket path. |
| The wrong node appears in `status` | Use the explicit Homebrew binary path and private `--socket`, then check the recorded node IP. |
| The node is online but SSH fails | `serve status` must show TCP 22, local loopback SSH must work, and tailnet policy must allow that port. |
| Local applications cannot reach tailnet addresses | Userspace mode provides no system routes. Use Heeler, another connected device, or configure an application-specific proxy separately. |
| Access stops after reboot or logout | The foreground daemon was not a persistent service. Restart Terminal A and verify the saved Serve configuration. |

Commands were checked against official documentation and Tailscale **1.104.1** CLI help on **2026-10-09**. See the [shared verification scope](overlay-networks.md#agent-handoff-and-evidence) for prior live validation. Repeat installation, login, and connection checks on the target Mac and tailnet.
