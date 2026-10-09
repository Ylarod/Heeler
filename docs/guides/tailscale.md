# Connect Through Tailscale

Use this guide to reach a Mac running herdr through Tailscale's standard macOS app. The Mac joins your tailnet through Tailscale's network extension and VPN configuration. Heeler joins the same tailnet with its own in-app node, so the iPhone or iPad needs no system VPN for this connection.

You need a Heeler build that includes [PR #426](https://github.com/ZingerLittleBee/Heeler/pull/426), a Tailscale account, and permission to add devices to that tailnet. For a Mac setup without a network extension or TUN interface, use [Tailscale in userspace mode](tailscale-userspace.md) instead.

## 1. Prepare the Mac

Complete [Prepare the Host](overlay-networks.md#prepare-the-host): enable macOS Remote Login for the intended local account, install and start herdr, and prepare the SSH authentication method you will use in Heeler. This guide uses the Mac's ordinary SSH server. Tailscale SSH (`tailscale up --ssh`) is a separate feature and is not required.

## 2. Install the macOS app and join the tailnet

1. Download the **Standalone** installer linked from [Install Tailscale on macOS](https://tailscale.com/docs/install/mac), install it, and open Tailscale. Use the standalone app for this path; the Homebrew CLI formula is covered in the userspace guide.
2. Follow the onboarding prompts to allow the Tailscale network extension and VPN configuration. On macOS 15 and later, extension approval is under **System Settings → General → Login Items & Extensions → Network Extensions**. Enable **Tailscale Network Extension**, authorize the change, and allow the VPN configuration when prompted. Earlier macOS versions use Privacy & Security; see the [official extension instructions](https://tailscale.com/docs/concepts/macos-sysext).
3. Use the Tailscale menu bar app to sign in to your tailnet. If your tailnet requires device approval, have its administrator approve this Mac.
4. In the [Tailscale admin console](https://login.tailscale.com/admin/machines), confirm that the Mac is connected. Record its Tailscale IPv4 address and machine name. Use the address assigned to this Mac, not its LAN address.

The standalone app uses macOS system networking, so other Mac applications can also use Tailscale routes. This differs from Heeler's app-only networking on iOS. Tailscale documents the packaging and networking differences in [macOS variants](https://tailscale.com/docs/concepts/macos-variants).

## 3. Join the same tailnet from Heeler

In Heeler, open **Settings → Overlay Networks**, add a network, and choose **Tailscale**. Fill in:

| Field | Value |
|---|---|
| Name | A label such as `Home tailnet` |
| Device name | A distinct name such as `heeler-iphone` |
| Coordination server | Leave blank for Tailscale |
| Auth key | Leave blank for browser sign-in |

![Heeler Add Network form with Tailscale selected, Device name, optional Coordination server, and optional Auth key fields](images/overlay-networks/tailscale-form.png)

**In this screen:** enter a recognizable Device name and leave Coordination server and Auth key blank for the browser sign-in route. Tap **Save**, then open the saved network and tap **Sign In**. [Open the full-size screenshot](images/overlay-networks/tailscale-form.png). [Capture details](overlay-networks.md#screenshots-and-maintenance).

Tap **Sign In** to open the browser, authenticate to the same tailnet as the Mac, then return to Heeler. It connects automatically, including after a longer stay in the browser. Approve the new Heeler device in the admin console if required. Once signed in, a disconnected network offers **Connect**; a connected network offers **Disconnect**. Heeler is a separate device from any Tailscale iOS app installed on the phone, with its own identity and address.

You can supply a Tailscale auth key instead of using browser sign-in. Obtain it from your tailnet administrator and enter it only in the Auth key field. Heeler stores it in the Keychain; tap **Connect** to join using the key. If your organization uses Headscale, enter its HTTPS coordination-server URL and follow that server's enrollment process on both devices.

Wait for the network to report **Connected**. Its detail screen shows this device's addresses and the peers visible to it. Being signed in alone does not grant SSH access: the tailnet's grants or ACLs must allow Heeler's device to reach the Mac's TCP port 22.

## 4. Add the Mac as a Host

Follow [Connect from Heeler](overlay-networks.md#connect-from-heeler). In the Host form, select your new network under **Network**, then use **Choose from Tailnet…** to select the Mac. Use **IP Address** for the first connection; **Machine Name** is also available. You can also open the Mac's peer on the network detail screen and choose **Add Host…**.

Set Port to `22`, User to the Mac's local SSH account, and choose the authentication method prepared in step 1. Leave Jump Host blank for this setup. Save, verify the SSH host-key fingerprint against the Mac, and complete the connection checks.

## 5. Verify and maintain the connection

Complete [Verify the connection](overlay-networks.md#verify-the-connection), including a test from a different network, such as the phone's cellular connection. Keep the Mac awake and connected to Tailscale while using Heeler remotely.

| Symptom | Check |
|---|---|
| The Mac does not appear in the peer picker | Both devices joined the same tailnet, device approvals are complete, and tailnet policy permits visibility and access. Try its Tailscale IPv4 address directly if necessary. |
| SSH times out | The Mac is awake, Tailscale is connected, and policy permits TCP 22 from Heeler's device. |
| SSH authentication fails | Use the Mac's local account and its authorized SSH key or password. Tailscale sign-in does not replace SSH authentication. |
| SSH connects but herdr checks fail | Return to the Host preparation and verification steps to check herdr installation, PATH, and session selection. |
| Heeler reports Signed out | Open the Overlay Network and tap Sign In to sign in again. |

Heeler's **Sign Out** targets its own node; it does not sign the Mac out. The current PR build has a source-confirmed race between sign-out and an active Host's automatic reconnect, so sign-out alone is not a reliable access-revocation step in that case. To revoke access, remove the intended Heeler device in the tailnet admin console and retire its saved auth key if applicable; preserve other devices and keys. Heeler stops overlay nodes when the app suspends after its Background Grace Period and rebuilds them when needed on return. Notifications use the Push Relay independently of this live SSH connection.

Official documentation and Heeler form labels were checked on **2026-10-09**. See the [shared verification scope](overlay-networks.md#agent-handoff-and-evidence) for the distinction between documented setup and live validation.
