-- -----------
-- vars
-- -----------

Factories = {       -- {NetUUID, Port}
    refinery      = {},
    fuelPlant     = {},
    plasticPlant  = {},
    rubberPlant   = {},
    preprocessing = {}
}

ExtFiles  = {
    '/include/utils.lua',
    '/include/network.lua',
    '/include/event.lua',
    '/include/scheduler.lua',
    '/include/logger.lua'
}

PlantName = 'master'

Ready = false


-- ----------
-- load helper funcs
-- ----------

if (not fs or not fs.isFile) then
    computer.panic('Expected Filesystem ref not set up!')
else
    for i, file in pairs(ExtFiles) do
        if not fs.isFile(file) then
            computer.panic(file .. ' not found!')
        else
            fs.doFile(file)
        end
    end
end


-- ----------
-- network functions
-- ----------

Net.msg.PONG[1] = 'handlePongRecv'
Net[Net.msg.PONG[1]] = function(self, srcUUID, name)

    Log:write(Log.INFO, 'Net:handlePongRecv() - ' .. srcUUID, name)

    if Factories[name] ~= nil then
        if Factories[name][1] ~= nil then
            Log:write(Log.INFO, 'Net:handlePongRecv() - Factory aleady added', name, srcUUID)
        else
            Factories[name][1] = srcUUID
        end
    else
        Log:write(Log.INFO, 'Net:handlePongRecv() - unexpected factory name received: ', name, srcUUID)
    end
end

Net.msg.ACK[1] = 'handleAccept'
Net[Net.msg.ACK[1]] = function(self, srcUUID, msg, data, moreData)

    Log:write(Log.ERROR, 'Net:handleAccept() - ', srcUUID, msg, data, moreData)

    -- todo: check send history if acked msg was actually send
    if msg == 'HANDSHAKE' then
        local idx = nil
        local taken = false
        for n, tbl in pairs(Factories) do
            if tbl[1] == srcUUID then
                idx = n
            end
            print(Net.ports[n])
            if Net.ports[n] ~= nil then
                taken = true
                Log:write(Log.WARN, 'Net:handleAccept() - port ' .. data .. ' already in use. Retry...')
                break
            end
        end
        if not taken and idx ~= nil then
            Factories[idx][2] = data
            Net.ports[idx] = data
        end
    else
        Log:write(Log.INFO, 'Net:handleAccept() - message ' .. msg ..  ' not supported')
    end
end


Net.msg.NAK[1] = 'handleDecline'
Net[Net.msg.NAK[1]] = function(self, srcUUID, msg, data, moreData)
    Log:write(Log.INFO, 'Net:handleDecline() - ', srcUUID, msg, data, moreData)

    -- todo: check send history if naked msg was actually send
    if msg == 'HANDSHAKE' then
        Log:write(Log.WARN, 'Net:handleDecline() - cannot connect to ' .. srcUUID ..  ', port ' .. data .. ' already take. Retry...')
        Schedule:add(1, TryConnect)
    else
        Log:write(Log.INFO, 'Net:handleDecline() - message ' .. msg ..  ' not supported')
    end
end


-- ----------
-- funcs
-- ----------

function TryConnect()
    local ok = true
    for n, tbl in pairs(Factories) do
        if tbl[1] == nil then
            Log:write(Log.WARN, 'Connect() - Error: missing expected factory:', n)
            ok = false
        elseif tbl[2] == nil then                           -- connection not yet established
            local port = math.random(1000, 1010)
            Schedule:add(1, Net.send, {Net, tbl[1], Net.ports.broadcast, 'HANDSHAKE', Net._self, port})
        end
    end

    if not ok then
        local delay = 5
        Log:write(Log.WARN, 'missing factory: retrying connection in ' .. delay .. 's')
        Schedule:add(delay, TryConnect)
    else
        Schedule:add(2, CheckConnection, 'CheckConnection')
    end
end

function CheckConnection()

    for k, v in pairs(Factories) do
        print(k, table.unpack(v))
    end
end


-- ----------
-- run
-- ----------

Log:write(Log.INFO, 'System started')

Net:init(PlantName)

Schedule:add(1, Net.send, {Net, nil, Net.ports.broadcast, 'PING', Net._self})
Schedule:add(3, TryConnect)
repeat
    event:update()

    Schedule:update(computer.millis())

until false
