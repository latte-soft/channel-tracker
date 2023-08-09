-- MIT License | Copyright (C) 2023 Latte Softworks <https://latte.to>

export type Config = {
    Workers: {
        Amount: number,
        CheckInterval: number,
        CheckIntervalLive: number,
    },
    CheckIntervals: {
        Versions: number,
        Flags: number,
    },
    Discord: {
        Username: string,
        AvatarUrl: string,
        LiveUpdatePingRoleId: string,
        PlatformEmojis: {
            Windows: string,
            MacOs: string,
        },
        Webhooks: {
            Live: {string},
            LivePre: {string},
            ZChannels: {string},
        },
    },
    TrackLive: boolean,
    ZChannels: {string},
}

return nil
