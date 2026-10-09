# Connect Heeler through ZeroTier

Use this guide to reach a Mac running herdr through a private ZeroTier Central network. The Mac runs the official ZeroTier One client; Heeler runs its own ZeroTier node inside the app. The iPhone or iPad needs neither the separate ZeroTier One app nor a system VPN configuration. On the Mac, the official client creates a system virtual network interface and applies the network's managed addresses and routes.

Use a Heeler build containing [PR #426](https://github.com/ZingerLittleBee/Heeler/pull/426), with **Settings > Overlay Networks** available. This guide was checked against Heeler source and the linked official documentation on **2026-10-09**. Start with [Overlay Networks](overlay-networks.md) for the shared SSH setup and connection model.

## Before you start

- Have administrator access to the Mac, a ZeroTier Central account with permission to manage the chosen network, and Heeler on your iPhone or iPad.
- Complete [Prepare the Host](overlay-networks.md#prepare-the-host): enable macOS Remote Login for the intended account, prepare herdr, register the Heeler Device Key, and obtain the Mac's SSH host-key fingerprint through a trusted local path.
- Keep the Mac awake and Heeler in the foreground during setup. Both need working network access to ZeroTier's roots and the network controller.
- Use a private network with manual device authorization and an IPv4 assignment range that does not overlap the Mac's local network. Leave custom Planet and Moon settings empty for this walkthrough.

Record these values as you reach each step. A node ID identifies a device; a network ID identifies the network; neither is the IP address used by SSH.

| Value | Where to get it | Used for |
| --- | --- | --- |
| `ZT_NETWORK_ID` | Central's network page, 16 hexadecimal digits | Joining the same network on both devices |
| Mac node ID | `zerotier-cli info`, 10 hexadecimal digits | Authorizing the correct Mac in Central |
| Heeler node ID | Heeler's ZeroTier form or network details, 10 hexadecimal digits | Authorizing Heeler separately from the Mac |
| Mac managed IP | Central's Mac member entry or `zerotier-cli listnetworks` | Heeler Host address, without a CIDR suffix |
| SSH username and port | The Mac setup in the shared guide | Heeler Host authentication and port |

## 1. Central: create a private network

Open the Central account that will own the network. [New Central](https://central.zerotier.com/) and [Legacy Central](https://my.zerotier.com/) use different navigation:

| Console | Create or select a network | Authorize a particular device later |
| --- | --- | --- |
| New Central | Select the default network in your organization, or use **Networks > New Network**. | Open **Member Devices**, match its node ID, then choose **Actions > Authorize** for that row. |
| Legacy Central | Use **Networks > Create A Network**, then open the network. | In **Members**, match the node's **Address** and select its **Auth?** checkbox. |

Keep access restricted to authorized members. In Legacy Central, set **Access Control** to **Private**. In the network settings, retain a usable managed IPv4 pool and its matching managed route. Copy the network ID and keep the member list open. Refer to the official [network management guide](https://docs.zerotier.com/networks/) for your console's settings.

**Checkpoint:** you have one private network ID and an address pool. You will authorize two different node IDs, one for the Mac and one for Heeler.

## 2. Mac: install ZeroTier One and join

Download the macOS installer from [ZeroTier's official download page](https://www.zerotier.com/download/) and complete its installation and any macOS permission prompts locally. The [official quickstart](https://docs.zerotier.com/quickstart/) also describes joining through the menu bar's **Join New Network…** action.

Alternatively, open Terminal on the Mac. Replace the placeholder with your own network ID before running:

```sh
ZT_NETWORK_ID='YOUR_16_HEX_NETWORK_ID'
sudo zerotier-cli info
sudo zerotier-cli join "$ZT_NETWORK_ID"
sudo zerotier-cli listnetworks
```

Record the Mac's node ID from `info`. A successful `join` command accepts the request; inspect `listnetworks` for the network's actual state. See the official [CLI reference](https://docs.zerotier.com/cli/).

Return to Central and authorize only the member whose node ID matches this Mac. Name the member so you can distinguish it from Heeler. Re-run `sudo zerotier-cli listnetworks` on the Mac.

**Checkpoint:** the selected network reports `OK PRIVATE` and has a managed address. Copy the Mac's address, for example `10.147.17.2` from `10.147.17.2/24`. If the network is still `ACCESS_DENIED`, finish authorizing that exact node before continuing. The official [create-a-network walkthrough](https://docs.zerotier.com/start/) shows this authorization transition.

## 3. Heeler and Central: join and authorize the app

Open **Settings > Overlay Networks > Add Network > Type > ZeroTier** to reach this form:

![Heeler ZeroTier form with Network ID, the device node ID, optional Moons, and default Planet settings](images/overlay-networks/zerotier-form.png)

**In this screen:** enter your 16-digit Network ID and copy **This Device > Node ID** for authorization in Central. Keep the default Planet and empty Moons for this walkthrough; both are now under **Advanced**, which the screenshot predates. The pictured node ID belongs to an isolated tutorial device; use your own. [Open the full-size screenshot](images/overlay-networks/zerotier-form.png). [Capture details](overlay-networks.md#screenshots-and-maintenance).

1. In Heeler, open **Settings > Overlay Networks > Add Network**.
2. Give the entry a recognizable **Name**, choose **Type > ZeroTier**, and paste `ZT_NETWORK_ID` into **Network ID**. Leave **Advanced** alone: no Moons, and the ZeroTier default Planet.
3. Copy **This Device > Node ID**, the generated Heeler node ID. If generation is still pending, add the network and copy the node ID from its status card after the first connection attempt.
4. Select **Add and Connect**. The network's screen opens and connects; **Waiting for authorization** is expected for a new private-network member, with the node ID on the status card and, for a network on ZeroTier's default roots, an **Open ZeroTier Central** button.
5. In Central, refresh the network's members and authorize the row matching the Heeler node ID. Authorizing the Mac alone does not authorize Heeler. Return to the network details in Heeler and allow its status to refresh; turn its switch on again if a prior attempt has ended and it is not connected.

Heeler shares one ZeroTier identity across its configured ZeroTier networks and keeps the private identity in the Keychain. That identity belongs to Heeler, independently of any other ZeroTier app installed on the same device. Keep both private identities on their own devices; Central needs only the public node IDs.

**Checkpoint:** Heeler shows **Connected** and an **Address** for this device, while Central lists both the Mac and Heeler as authorized members. Heeler's address identifies the phone or tablet; the next step uses the Mac's address instead.

## 4. Heeler: add the Mac as a Host

Follow [Connect from Heeler](overlay-networks.md#connect-from-heeler), using these values:

| Host field | Value |
| --- | --- |
| Network | The ZeroTier entry you just connected |
| Address | The Mac's managed ZeroTier IP, with no `/prefix` suffix |
| Port | The Mac's SSH port, normally `22` |
| Username and authentication | The account and Device Key prepared in the shared guide |
| Jump Host | Leave unset for a Mac directly reachable on this ZeroTier network |

Heeler's ZeroTier backend accepts IP literals, including IPv6, rather than DNS names. Copy the managed IP from Central or the Mac's `listnetworks` output. Heeler's **Members** list and the **Roots** in its **Diagnostics** show transport paths (touch and hold a member to copy one), which may be public IP addresses and ports; those are not the managed addresses to enter for a Host. ZeroTier therefore has no managed-address peer picker in Heeler.

Verify the Mac's SSH fingerprint when prompted, complete the Host checks, and follow [Verify the connection](overlay-networks.md#verify-the-connection). Success means the intended herdr inventory appears and a disposable terminal accepts input and returns output. Merely seeing an overlay address does not establish SSH authentication or herdr readiness.

If another trusted computer is already authorized on the same ZeroTier network, an independent `ssh -p <SSH_PORT> <SSH_USERNAME>@<MAC_MANAGED_IP>` check can help isolate Mac SSH setup from Heeler setup. Use that computer's own authorized SSH identity and verify the host fingerprint. ZeroTier's [remote-access guide](https://docs.zerotier.com/remotedesktop/) describes the managed-IP SSH path.

## Troubleshooting

| Symptom | Check and next action |
| --- | --- |
| Heeler cannot save the network | Paste the 16-digit network ID, not the 10-digit node ID. Remove incomplete Moon rows for the default-root setup. |
| Waiting for authorization or Mac `ACCESS_DENIED` | Match and authorize the exact device node ID on the intended private network. Each device needs its own authorization. |
| Mac `REQUESTING_CONFIGURATION` or Heeler times out without an address | Check the network ID, internet access, and controller reachability. Open Heeler's network **Diagnostics** to distinguish joined state, addresses, and root activity. |
| Authorized but no managed IPv4 | Check the network's address pool and matching managed route in Central; use an address actually assigned to the Mac. |
| Mac `PORT_ERROR` | Check the installed client's network-interface permissions using ZeroTier's [macOS troubleshooting guide](https://docs.zerotier.com/faq/macos-porterror/). Its older macOS screenshots and restart commands may differ from your OS. |
| Connected, but SSH fails | Confirm the Host uses the Mac's managed IP and selected ZeroTier entry; then check Remote Login, the login account, SSH port, network rules, firewall, and Device Key as described in the shared guide. |
| No members appear in Heeler | The list describes nodes contacted by this process across its ZeroTier networks. A member can appear only after traffic; use Central's managed IP to attempt the Host connection. |
| A connection is lost after backgrounding Heeler | Return to the app and let the Host reconnect. The in-app node does not provide an always-on system VPN; see the shared guide's lifecycle notes. |

For CLI errors about a missing or unreadable authentication token, use the locally authorized administrator account and `sudo`; keep `authtoken.secret` private. When sharing diagnostics, remove addresses or identifiers you do not want to disclose.

## Advanced: Planet and Moon settings

Heeler offers **Import Planet File…** for an operator-provided planet-type World file up to 16 KB; a moon file is rejected there. **Add Moon** instead takes a 10-to-16-digit hexadecimal World ID and a 10-digit root-node Seed, both nonzero. These settings are unnecessary for the Central walkthrough.

The current implementation has a known startup limitation: a new Heeler process waits for its first connection to ZeroTier's official roots before it installs a network's custom Planet or Moons. If only the private roots are reachable, initial connection can time out even when those roots work. This is a source-confirmed ordering defect, not an instruction to disable SSH or network security. Treat a deployment that requires independence from the official roots as unsupported by this build until that defect is fixed and the deployment is verified.

Configured custom roots join the same process-wide root set as other ZeroTier networks. Lookups and relays can traverse those roots across networks; network-specific Planet settings do not provide independent root privacy. See [ADR 0021](../adr/0021-in-process-overlay-networks.md) for the design and trade-off.

The existing Heeler live check used a controller-less IPv6 ad-hoc network to verify SSH, terminal traffic, and background recovery. It did not validate this Central enrollment procedure, private-controller authorization, custom Planet/Moon deployments, or overlapping IPv4 networks. Those remain separate acceptance checks; an ad-hoc network is not a substitute for a private Central network.

## Stop using the network

Turning off the network's switch ends the current network connection and retains its configuration and identity. An active Host can request a connection again. To retire the network, first move its Hosts to another working route or remove those Host entries, then delete the network entry.

On the Mac, leave only the network you intend to remove:

```sh
sudo zerotier-cli leave "$ZT_NETWORK_ID"
sudo zerotier-cli listnetworks
```

Check that its entry is gone. In Central, deauthorize the corresponding Mac or Heeler member to revoke that identity's network access. Local disconnect or deletion does not revoke controller authorization. Preserve the Mac's other networks and other members' access; retain SSH host-key verification and normal SSH account restrictions while the network is in use.

## Sources and maintenance

Official documentation checked on **2026-10-09**: [Quickstart](https://docs.zerotier.com/quickstart/), [Network Groups and Networks](https://docs.zerotier.com/networks/), [Create a Network](https://docs.zerotier.com/start/), [CLI](https://docs.zerotier.com/cli/), [macOS](https://docs.zerotier.com/macos/), and [Remote Desktop / SSH](https://docs.zerotier.com/remotedesktop/).

Heeler behavior was checked against [the network form and details](../../Sources/Heeler/Settings/OverlayNetworksSettingsView.swift), [the Host form](../../Sources/Heeler/Hosts/HostFormView.swift), [ZeroTierNetworkNode](../../Packages/HeelerOverlay/Sources/HeelerOverlay/ZeroTierNetworkNode.swift), and [ZeroTierRuntime](../../Packages/HeelerOverlay/Sources/HeelerOverlay/ZeroTierRuntime.swift). Recheck the startup limitation and the verification scope when those implementations change.
