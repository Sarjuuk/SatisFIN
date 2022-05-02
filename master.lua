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

Splitter = component.proxy('C61FBDA34A128345F49EED82E89CBBF4')

ExtFiles  = {
    '/include/utils.lua',
    '/include/network.lua',
    '/include/event.lua',
    '/include/scheduler.lua',
    '/include/logger.lua'
}

PlantName = 'master'

Ready = false

ReqRubber  = 0
ReqPlastic = 0

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

    Log:write(Log.DEBUG, 'Net:handlePongRecv() - ' .. srcUUID, name)

    if Factories[name] ~= nil then
        if Factories[name][1] ~= nil then
            Log:write(Log.WARN, 'Net:handlePongRecv() - Factory aleady added', name, srcUUID)
        else
            Factories[name][1] = srcUUID
        end
    else
        Log:write(Log.WARN, 'Net:handlePongRecv() - unexpected factory name received: ', name, srcUUID)
    end
end

Net.msg.RSP_PR_STATE[1] = 'handleResponsePlantStateRcv'
Net[Net.msg.RSP_PR_STATE[1]] = function(self, srcUUID, name, cur, max)
    print(srcUUID, name, cur, max)
end

Net.msg.ACK[1] = 'handleAccept'
Net[Net.msg.ACK[1]] = function(self, srcUUID, msg, data, moreData)

    Log:write(Log.DEBUG, 'Net:handleAccept() - ', srcUUID, msg, data, moreData)

    -- todo: check send history if acked msg was actually send

    if HandleAccept[msg] == nil then
        Log:write(Log.ERROR, 'Net:handleAccept() - message ' .. msg ..  ' not supported')
    else
        HandleAccept[msg](srcUUID, msg, data, moreData)
    end
end


Net.msg.NAK[1] = 'handleDecline'
Net[Net.msg.NAK[1]] = function(self, srcUUID, msg, data, moreData)
    Log:write(Log.DEBUG, 'Net:handleDecline() - ', srcUUID, msg, data, moreData)

    -- todo: check send history if naked msg was actually send

    if HandleDecline[msg] == nil then
        Log:write(Log.ERROR, 'Net:handleDecline() - message ' .. msg ..  ' not supported')
    else
        HandleDecline[msg](srcUUID, msg, data, moreData)
    end
end


HandleAccept = {
    HANDSHAKE = function(srcUUID, msg, data, moreData)
        local idx = nil
        local inUse = false
        for n, tbl in pairs(Factories) do
            if tbl[1] == srcUUID then
                idx = n
            end
            if data == tbl[2] then
                inUse = true
                Log:write(Log.WARN, 'Net:handleAccept() - {' .. msg .. '} port ' .. data .. ' already in use. Retry...')
                Schedule:add(1, TryConnect)
                break
            end
        end
        if not inUse and idx ~= nil then
            Factories[idx][2] = data
            Net.ports[idx] = data
            Net.card:open(data)
        end
    end,
    REQ_ITEM = NOP,
    REQ_STATUS = function(srcUUID, msg, data, moreData)

    end
}

HandleDecline = {
    HANDSHAKE = function(srcUUID, msg, data, moreData)
        Log:write(Log.WARN, 'Net:handleDecline() - {' .. msg .. '} cannot connect to ' .. srcUUID ..  ', port ' .. data .. ' already in use. Retry...')
        Schedule:add(1, TryConnect)
    end,
    REQ_ITEM = function(srcUUID, msg, data, moreData)
        if data == 'Plastic' then
            ReqPlastic = ReqPlastic + moreData
        elseif data == 'Rubber' then
            ReqRubber = ReqRubber + moreData
        else
            Log:write(Log.WARN, 'Net:handleAccept() - {' .. msg .. '} unexpected item type:', data)
        end
    end
}

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
            local port = math.random(1000, 1100)
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
    if Ready then
        return
    end

    for n, tbl in pairs(Factories) do
        if Net.ports[n] ~= tbl[2] then
            computer.panic('[PANIC] CheckConnection() - ports for ' .. n .. ':' .. tbl[2] .. ' different in NIC :' .. Net.ports[n])
        elseif tbl[2] == nil then
            Schedule:add(1, TryConnect)
            return
        end
    end

    Log:write(Log.INFO, 'Systems connected - ready!')
 -- Schedule:add(0.1, Net.send, {Net, Factories.refinery[1],      Factories.refinery[2],      'REQ_STATUS'}, 1)
 -- Schedule:add(0.3, Net.send, {Net, Factories.fuelPlant[1],     Factories.fuelPlant[2],     'REQ_STATUS'}, 1)
    Schedule:add(0.5, Net.send, {Net, Factories.preprocessing[1], Factories.preprocessing[2], 'REQ_STATUS'}, 1)
 -- Schedule:add(0.7, Net.send, {Net, Factories.plasticPlant[1],  Factories.plasticPlant[2],  'REQ_STATUS'}, 1)
 -- Schedule:add(0.9, Net.send, {Net, Factories.rubberPlant[1],   Factories.rubberPlant[2],   'REQ_STATUS'}, 1)
    Ready = true
end

function HandleSplitter()
    -- Outputs
    -- 0 - Rubber
    -- 1 - None
    -- 2 - Plastic

    local item = Splitter:getInput()
    if not item or not item.type then
        return
    end

    if item.type.name == 'Rubber' and Splitter:canOutput(0) then
        Splitter:transferItem(0)

    elseif item.type.name == 'Plastic' and Splitter:canOutput(2) then
        Splitter:transferItem(2)
    end
end

function EvSplitterOut(port, item)
    if port == 0 then
        ReqRubber = ReqRubber + 1
    elseif port == 2 then
        ReqPlastic = ReqPlastic + 1
    end
end

function EvSplitterIn(item)
    print('EvSplitterIn', item)
end


-- ----------
-- run
-- ----------

Log:write(Log.INFO, 'System started')

Net:init(PlantName)

-- event:register(Splitter, {EvSplitterIn}, 'ItemRequest')
event:register(Splitter, {EvSplitterOut}, 'ItemOutputted')

Schedule:add(1, Net.send, {Net, nil, Net.ports.broadcast, 'PING', Net._self})
Schedule:add(3, TryConnect)

repeat
    event:update()

    Schedule:update(computer.millis())

    HandleSplitter()
    if ReqRubber > 0 then
        Net:send(Factories.preprocessing[1], Factories.preprocessing[2], 'REQ_ITEM', 'Rubber', ReqRubber)
        ReqRubber = 0
    end
    if ReqPlastic > 0 then
        Net:send(Factories.preprocessing[1], Factories.preprocessing[2], 'REQ_ITEM', 'Plastic', ReqPlastic)
        ReqPlastic = 0
    end

until false
