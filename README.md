# Veil

[فارسی](README.fa.md)

**Veil is a modern macOS app for connecting with CDN profiles without the usual setup headache, powered by low-level SNI spoofing.**

Import your profiles, test them, choose the best one, and connect. Veil prepares the connection and applies the right macOS settings for you, so you do not have to juggle scripts, terminals, or separate clients.

<table>
  <tr>
    <td align="center" width="50%">
      <strong>Dashboard</strong><br />
      <img src="macos-app/screenshot/app-dashboard.png" alt="Veil dashboard" width="100%" />
    </td>
    <td align="center" width="50%">
      <strong>Profiles</strong><br />
      <img src="macos-app/screenshot/profiles.png" alt="Veil profiles" width="100%" />
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>Settings</strong><br />
      <img src="macos-app/screenshot/settings.png" alt="Veil settings" width="100%" />
    </td>
    <td align="center">
      <strong>Menu bar</strong><br />
      <img src="macos-app/screenshot/menubar.png" alt="Veil menu bar" width="100%" />
    </td>
  </tr>
</table>

## Features

- **Built-in Low-Level SNI Spoofing:** Forges TLS ClientHello packets and uses TCP sequence tricks to bypass SNI-based domain filtering on restrictive networks.
- **Full macOS Packet Tunnel Mode:** Native NetworkExtension utun integration to capture system-wide traffic, eliminating per-app SOCKS/HTTP proxy configuration.
- **System Proxy Mode:** Light-touch SOCKS5 / HTTP proxy setup when you only need application-level routing.
- **Geosite & Domain Bypass Routing:** Flexible routing engine supporting Geosite rules (e.g., Iranian/Chinese sites, ads, streaming) and custom domain/IP bypass lists so local traffic bypasses the proxy entirely.
- **Smart Profile Management & Real Latency Testing:** Import subscription links (VLESS, Shadowsocks, Trojan, etc.), drag-and-drop text/JSON profiles, batch ping profiles end-to-end, filter broken configurations, and export reconstructed profile links.
- **Live Connection & Egress Analytics:** Interactive route visualization card, real-time egress IP / location lookup, session data counters, and live activity graphs.
- **Menu Bar Companion:** Quick toggle connection, switch active profile, check egress status, and launch options straight from the macOS menu bar.
- **Zero-Setup Universal macOS App:** Self-contained bundle with bundled Xray-core, custom Python listener binary, and helper tools. No terminal, Python, or core installation needed.

## Download

Get the latest **DMG** from [GitHub Releases](https://github.com/uidops/veil/releases).

After opening the DMG, drag **Veil** to **Applications**.

Because Veil is an open-source community build, macOS may ask you to confirm the first launch. If that happens, open **System Settings -> Privacy & Security** and choose **Open Anyway**.

## Quick Start

1. Open Veil.
2. Approve the one-time helper permission on initial run.
3. Import or paste your profiles.
4. Ping them and select an active profile.
5. Choose your mode (**Tunnel Mode** for full system traffic or **System Proxy**) and press **Connect**.

Bring a working profile, and Veil takes care of the rest.

## Donations

If Veil helps you, you can support development:

- **TON:** `UQD1OPPvt1PgKqiU2xYzb5MX3M9pIxz32SpdskkLzNmJn1na`
- **USDT (BEP20):** `0x4FcB75ECaf89653aB4bB7B8706202823617ACbAB`
- **TRX (TRON):** `TD6jvEDBQFYVEw7tDmvmnFbmi29GvyEAPZ`

## License

See [LICENSE](LICENSE).
