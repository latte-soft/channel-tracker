# Roblox Channel Tracker

A basic Roblox channel deployment tracker that utilizes [Discord Webhooks](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks) for notifying changes.

## Setup

* Clone/[Download](https://github.com/latte-soft/channel-tracker/zipball/main) the Repository

```txt
git clone https://github.com/latte-soft/channel-tracker.git
```

* Install [`filiptibell/lune`](https://github.com/filiptibell/lune) automatically via [Aftman](https://github.com/LPGhatguy/aftman)

```txt
aftman install
```

* [Add a `config.json` file](#configjson-file-template), and just run!

```txt
lune main 
```

<sup><i>Just a heads up, you can run "lune main config-file:path/to/config/file" to specify another path to your config file, as the default is just "config.json"</i></sup>

### `config.json` File Template

*(The channels in `"ZChannels"` are just a few examples, as to not clutter the template)*

```json
{
    "Workers": {
        "Amount": 20,
        "CheckInterval": 5
    },
    "Discord": {
        "Username": "AvLab",
        "AvatarUrl": "https://media.discordapp.net/attachments/962055279099383829/1109605825506459808/AvLab.png",
        "LiveUpdatePingRoleId": "1109607945152503838",
        "PlatformEmojis": {
            "Windows": "<:windows:1109709970917826580>",
            "MacOs": "<:osx:1109720452772925522>"
        },
        "Webhooks": {
            "Live": ["https://discord.com/api/webhooks/123/<server_id>"],
            "ZChannels": ["https://discord.com/api/webhooks/321/<server_id>"]
        }
    },
    "TrackLive": true,
    "ZChannels": [
        "zintegr
    ]
}
```
