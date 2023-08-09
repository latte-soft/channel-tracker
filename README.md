## ⚠️ Notice of Archival

This repository has been archived due to recent changes by Roblox's build-team with files on S3 per channel (`/version`, `/versionQTStudio`, `/mac/version`, and `/mac/versionStudio`) no longer being updated for alternate channels (e.g. `zcanary`, `zintegration` etc), making this version of our tracker near-useless outside of tracking [`LIVE`](https://setup.rbxcdn.com/DeployHistory.txt) (production).

We're still hosting a **proprietary** version of this tracker in the [Latte Softworks Discord Server](https://latte.to/discord), and this repository is to serve as display for what was once possible to track!

___

# Roblox Channel Tracker

A basic Roblox channel deployment tracker that utilizes [Discord Webhooks](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks) for notifying changes.

*This tracker is also hosted officially in the [Latte Softworks Discord Server](https://latte.to/discord) :)*

## Setup

* Clone/[Download](https://github.com/latte-soft/channel-tracker/zipball/main) the Repository

```txt
git clone https://github.com/latte-soft/channel-tracker.git
```

* Install [`filiptibell/lune`](https://github.com/filiptibell/lune) automatically via [Aftman](https://github.com/LPGhatguy/aftman)

```sh
aftman install
```

* [Add a `config.json` file](#configjson-file-template), and just run!

```sh
lune main
```

<sup><i>Just a heads up, you can run "lune main config-file:path/to/config/file" to specify another path to your config file, as the default is just "config.json"</i></sup>

### `config.json` File Template

*(The channels in `"ZChannels"` are just a few examples, as to not clutter the template.*

```json
{
    "Workers": {
        "Amount": 8,
        "CheckInterval": 10,
        "CheckIntervalLive": 25
    },
    "Discord": {
        "Username": "AvLab",
        "AvatarUrl": "https://media.discordapp.net/attachments/962055279099383829/1109605825506459808/AvLab.png",
        "PlatformEmojis": {
            "Windows": "<:windows:1109709970917826580>",
            "MacOs": "<:osx:1109720452772925522>"
        },
        "Webhooks": {
            "Live": ["https://discord.com/api/webhooks/123/<server_id>"],
            "LivePre": ["https://discord.com/api/webhooks/123/<server_id>"],
            "ZChannels": ["https://discord.com/api/webhooks/321/<server_id>"]
        }
    },
    "TrackLive": true,
    "ZChannels": [
        "zintegration",
        "zcanary",
        "znext"
    ]
}
```

*(Here's what's actually fully required in the config, as an example)*

```json
{
    "Workers": {
        "Amount": 1,
        "CheckInterval": 0
    },
    "Discord": {
        "Webhooks": {}
    }
}
```

___

## License

A copy of the MIT License is also located in this repository @ [LICENSE.txt](LICENSE.txt).

```txt
MIT License

Copyright (c) 2023 Latte Softworks <https://latte.to>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```
