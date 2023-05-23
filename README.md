# Roblox Channel Tracker

A basic Roblox channel deployment tracker that utilizes [Discord Webhooks](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks) for notifying changes.

*This tracker is also hosted officially in the [Latte Softworks Discord Server](https://latte.do) :)*

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

*(The channels in `"ZChannels"` are just a few examples, as to not clutter the template.*

```json
{
    "Workers": {
        "Amount": 20,
        "CheckInterval": 5
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

A copy of the GPLv3 is located in this repository @ [LICENSE.txt](LICENSE.txt). If you're unable to access this file, see the notice below:

```txt
Copyright (C) 2023 Latte Softworks <latte.to>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
