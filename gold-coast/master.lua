-- -----------
-- vars
-- -----------

Master = Plant:init({
    name     = 'master',
    graphs   = {},
    request  = {
        rubber  = 0,
        plastic = 0
    },

    addData = function(self, srcUUID, type, name, cur, max)
        for i, tbl in pairs(Factories) do
            if tbl[1] == srcUUID then
                self.graphs[tbl[4]]:addData(srcUUID, type, name, cur, max)
                return
            end
        end
    end,

    onStartup = function(self)
        CLS(GPU)
        GPU:setText(0, 0, 'Booting...')
        GPU:flush()

        -- self:loadVars('request') -- fix table delimiter issue

        self.graphs[1] = Graph:new():init(GPU, 22, 1, 1)
        self.graphs[2] = Graph:new():init(GPU, 22, 1, 30)

        Schedule:add(1, Net.send, {Net, nil, Net.ports.broadcast, 'PING', Net._self}, 3)
        Schedule:add(3, TryConnect)

        self.state = PLANT_STATE.CONNECT_WAIT
    end,

    onConnect = function(self)

    end,

    onPause = function(self)

    end,

    onWorking = function(self)

        if self.request.rubber > 0 then
            Net:send(Factories.preprocessing[1], Factories.preprocessing[2], 'REQ_ITEM', 'Rubber', self.request.rubber)
            self.request.rubber = 0
        end
        if self.request.plastic > 0 then
            Net:send(Factories.preprocessing[1], Factories.preprocessing[2], 'REQ_ITEM', 'Plastic', self.request.plastic)
            self.request.plastic = 0
        end

        self.graphs[1]:draw()
        self.graphs[2]:draw()
    end,

    onDisconnect = function(self)
        CLS(GPU)
        GPU:setText(0, 0, 'Shutdown: Waiting for clients..')
        local i = 0
        local j = 0
        for n, adr in pairs(Factories) do
            i = i + 1
            if type(adr[1]) == 'string' then
                GPU:setText(0, i, '  ' .. n .. '.. ')
            elseif adr[1] then
                GPU:setText(0, i, '  ' .. n .. '.. ')
                GPU:setForeground(0, 1, 0, 1)
                GPU:setText(#n + 5, i, 'OK')
                GPU:setForeground(1, 1, 1, 1)
                j = j + 1
            else
                GPU:setText(0, i, '  ' .. n .. '.. ')
                GPU:setForeground(1, 0, 0, 1)
                GPU:setText(#n + 5, i, 'ERR')
                GPU:setForeground(1, 1, 1, 1)
            end
        end
        GPU:flush()

        if i == j then
            Schedule:add(2, computer.reset)
            PlantState = PLANT_STATE.SHUTDOWN
            Reset:setColor(1, 0, 0, 1)
        end
    end,

    onShutdown = function(self)
        CLS(GPU)
        GPU:setText(0, 0, 'Shutting down...')
        GPU:flush()

        if self.hold then
            return
        end

        self.hold = true
        -- self:saveVars('request') -- fix table delimiter issue
    end
})

Factories = {       -- {NetUUID, Port, Schedule, graphIdx}
    refinery      = {nil, nil, nil, 1},
    fuelPlant     = {nil, nil, nil, 1},
    preprocessing = {nil, nil, nil, 1},
    plasticPlant  = {nil, nil, nil, 2},
    rubberPlant   = {nil, nil, nil, 2}
}


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


Net.msg.RSP_PR_STATE[1] = 'handleResponseProdStateRcv'
Net[Net.msg.RSP_PR_STATE[1]] = function(self, srcUUID, name, type, cur, max)
    Plant:addData(srcUUID, 1, name, cur, max)
end


Net.msg.RSP_BU_STATE[1] = 'handleResponseBufferStateRcv'
Net[Net.msg.RSP_BU_STATE[1]] = function(self, srcUUID, name, type, cur, max)
    Plant:addData(srcUUID, 2, name, cur, max)
end


HandleAccept = {
    CONNECT = function(srcUUID, msg, data, moreData)
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
    REQ_PLANT_STATUS = function(srcUUID, msg, data, moreData)

    end,
    REBOOT = function(srcUUID, msg, data)
        for i, adr in pairs(Factories) do
            if adr[1] == srcUUID then
                Factories[i][1] = true
                return
            end
        end
    end
}

HandleDecline = {
    CONNECT = function(srcUUID, msg, data, moreData)
        Log:write(Log.WARN, 'Net:handleDecline() - {' .. msg .. '} cannot connect to ' .. srcUUID ..  ', port ' .. data .. ' already in use. Retry...')
        Schedule:add(1, TryConnect)
    end,
    REQ_ITEM = function(srcUUID, msg, data, moreData)
        if data == 'Plastic' then
            self.request.plastic = self.request.plastic + moreData
        elseif data == 'Rubber' then
            self.request.rubber = self.request.rubber + moreData
        else
            Log:write(Log.WARN, 'Net:handleAccept() - {' .. msg .. '} unexpected item type:', data)
        end
    end,
    REBOOT = function(srcUUID, msg, data)
        for i, adr in pairs(Factories) do
            if adr[1] == srcUUID then
                Factories[i][1] = false
                return
            end
        end
    end
}


-- ----------
-- components
-- ----------

Splitter = component.proxy('C61FBDA34A128345F49EED82E89CBBF4')

GPU = computer.getPCIDevices(findClass("GPUT1"))[1]
assert(GPU, 'No GPU found!')

Screen = component.proxy(component.findComponent(findClass("Screen"))[1])
assert(Screen, 'No Screen found!')

Reset = component.proxy(component.findComponent('ButtonHolder')[1]):getModule(0, 0)
assert(Reset, 'No Reset Button found!')

NetPanel = component.proxy(component.findComponent('NetPanel')[1])
NetRecvLED = NetPanel:getModule(0, 0)
NetSendLED = NetPanel:getModule(1, 0)


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
            Schedule:add(1, Net.send, {Net, tbl[1], Net.ports.broadcast, 'CONNECT', Net._self, port})
        end
    end

    if not ok then
        local delay = 5
        Log:write(Log.WARN, 'missing factory: retrying connection in ' .. delay .. 's')
        Schedule:add(delay - 2, Net.send, {Net, nil, Net.ports.broadcast, 'PING', Net._self})
        Schedule:add(delay, TryConnect)
    else
        Schedule:add(2, CheckConnection, 'CheckConnection')
    end
end

function CheckConnection()
    -- if PlantState ~= PLANT_STATE.STARTUP then
    --     return
    -- end

    for n, tbl in pairs(Factories) do
        if Net.ports[n] ~= tbl[2] then
            computer.panic('[PANIC] CheckConnection() - ports for ' .. n .. ':' .. tbl[2] .. ' different in NIC :' .. Net.ports[n])
        elseif tbl[2] == nil then
            Schedule:add(1, TryConnect)
            return
        end
    end

    Log:write(Log.INFO, 'Systems connected - ready!')
    Factories.refinery[3]      = Schedule:add(0.1, Net.send, {Net, Factories.refinery[1],      Factories.refinery[2],      'REQ_PLANT_STATUS'}, 2)
    Factories.fuelPlant[3]     = Schedule:add(0.3, Net.send, {Net, Factories.fuelPlant[1],     Factories.fuelPlant[2],     'REQ_PLANT_STATUS'}, 2)
    Factories.preprocessing[3] = Schedule:add(0.5, Net.send, {Net, Factories.preprocessing[1], Factories.preprocessing[2], 'REQ_PLANT_STATUS'}, 2)
    Factories.plasticPlant[3]  = Schedule:add(0.7, Net.send, {Net, Factories.plasticPlant[1],  Factories.plasticPlant[2],  'REQ_PLANT_STATUS'}, 2)
    Factories.rubberPlant[3]   = Schedule:add(0.9, Net.send, {Net, Factories.rubberPlant[1],   Factories.rubberPlant[2],   'REQ_PLANT_STATUS'}, 2)
    PlantState = PLANT_STATE.WORKING
    CLS(GPU)
    Reset:setColor(0, 1, 0, 2)
end

-- basic splitter logic
function HandleSplitter()
    local item = Splitter:getInput()
    if not item or not item.type then
        return
    end

    if item.type.name == 'Rubber' and Splitter:canOutput(PORT.LEFT) then
        Splitter:transferItem(PORT.LEFT)
    elseif item.type.name == 'Plastic' and Splitter:canOutput(PORT.RIGHT) then
        Splitter:transferItem(PORT.RIGHT)
    end
end


-- ----------
-- run
-- ----------

Log:start()

Log:write(Log.INFO, 'System started')

Net:init(Plant.name, NetRecvLED, NetSendLED)
Net:send(nil, Net.ports.broadcast, 'PING', Net._self)

GPU:bindScreen(Screen)
GPU:setSize(160, 56)

Reset:setColor(0.5, 0.5, 0, 1)

event:register(Splitter, 'ItemRequest', NOP)
event:register(Splitter, 'ItemOutputted', function (port, item)
    if port == 0 then
        Plant.request.rubber = Plant.request.rubber + 1
    elseif port == 2 then
        Plant.request.plastic = Plant.request.plastic + 1
    end
end)

-- event:register(GPU, 'OnMouseMove', function(x, y, btn)
--     -- btn: 1 left; 2 right
--     GPU:setText(x, y, btn)
--     GPU:flush()
-- end)
-- event:register(GPU, 'OnMouseDown', function(x, y, btn)
--     -- btn: 1 left; 2 right
--     GPU:setText(x, y, btn)
--     GPU:flush()
-- end)
-- event:register(GPU, 'OnMouseUp', function(x, y, btn)
--     -- btn always 0
--     GPU:setText(x, y, btn)
--     GPU:flush()
-- end)


event:register(Reset, 'Trigger', function ()
    -- Plant.state = PLANT_STATE.DISCONNECT_WAIT
    Plant.state = PLANT_STATE.SHUTDOWN
    Reset:setColor(1, 0.5, 0, 1)
    for n, adr in pairs(Factories) do
        Net:send(adr[1], adr[2], 'REBOOT')
        if adr[3] then
            Schedule:remove(adr[3])
            Factories[n][3] = nil
        end
    end
end)


-- ----------
-- OB1
-- ----------

repeat
    event:update()

    Schedule:update(computer.millis())

    Plant:update()

    HandleSplitter()

    GPU:setText(152, 55, Time(computer.time()))
until false
