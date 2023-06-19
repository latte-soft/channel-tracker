-- GPLv3 | Copyright (C) 2023 Latte Softworks <latte.to>

export type WebhookObject = {[string]: any}

local net = require("@lune/net")
local task = require("@lune/task")
local serde = require("@lune/serde")

-- Setup everything used in the main thread
local QueueIsRunning = false -- Used for `WebhookQueue.Stop()`
local QueueTable = {}

-- Start the running thread to listen to the queue
local function Start(waitInterval: number?)
    waitInterval = waitInterval or 3

    if QueueIsRunning then -- Already running, must've been a mistake
        return
    end

    QueueIsRunning = true

    task.spawn(function()
        while QueueIsRunning do
            repeat
                task.wait()
            until #QueueTable >= 1
            local WebhookEntry = QueueTable[1]

            local WebhookUrl = WebhookEntry[1]
            local WebhookObject: WebhookObject = WebhookEntry[2]

            local Encoded = serde.encode("json", WebhookObject)
        
            local DiscordResponse = net.request({
                url = WebhookUrl,
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                },
                body = Encoded
            })

            assert(DiscordResponse.ok, `[!] Error in webhook request ({DiscordResponse.statusCode}): {DiscordResponse.body}`)

            -- Wait the interval now..
            task.wait(waitInterval)

            -- Finnaly, remove the current webhook object from the queue, which also triggers `Await()`
            table.remove(QueueTable, 1)
        end
    end)
end

-- Stop the running thread
local function Stop()
    QueueIsRunning = false
end

-- Add to the Webhook post queue
local function Add(webhookUrl: string, webhookObject: WebhookObject)
    table.insert(QueueTable, {
        [1] = webhookUrl,
        [2] = webhookObject,
    })
end

-- Clear all entries from the queue
local function Clear()
    for Index in QueueTable do
        QueueTable[Index] = nil
    end
end

-- Await in the current running thread for the queue to finish all tasks
local function Await()
    repeat
        task.wait()
    until #QueueTable == 0
end

return {
    Start = Start,
    Stop = Stop,
    Add = Add,
    Clear = Clear,
    Await = Await,
}
