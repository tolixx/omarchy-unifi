# omarchy-unifi

UniFi in the Omarchy bar: WAN traffic, active clients, and a per-device VPN switch built on UniFi policy routes ("traffic routes").

Work in progress. `bin/omarchy-unifi` talks to the gateway with an API key (UniFi Network 10.6, tested on a UniFi Express 7); the shell plugin (bar widget + panel) comes next.

## Setup

1. In UniFi: Settings > Control Plane > Integrations > Create API Key.
2. Save it to `~/.config/omarchy-unifi/key` (`chmod 600`).
3. `~/.config/omarchy-unifi/config.json`: `{"host": "https://192.168.1.1", "site": "default"}`

## CLI

```
omarchy-unifi bar                    # {"text": "↓ 6.2 Mbit/s ↑ 6.5 Mbit/s", "tooltip": ..., "class": "ok"}
omarchy-unifi clients                # active clients, rates, and the VPN route each one is on
omarchy-unifi routes                 # policy routes with their VPN
omarchy-unifi vpn <route-id> on|off  # switch a device's route on or off
```
