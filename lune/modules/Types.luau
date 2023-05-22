export type Config = {
    Workers: {
        Amount: number,
        CheckInterval: number,
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
            ZChannels: {string},
        },
    },
    TrackLive: boolean,
    ZChannels: {string},
}

return nil