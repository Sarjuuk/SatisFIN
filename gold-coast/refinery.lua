-- -----------
-- vars
-- -----------

RcvLED, SndLED = nil, nil

Refinery = Plant:init(
    {
        name  = 'refinery',
        reset = false,

        onStartup = function(self)
            Log:write(Log.INFO, 'Startup')
            self:stop(true) -- init stopped
        end,

        startup = function(self)
            -- nothing to wait for, go to next step
            self:setState(PLANT_STATE.CONNECT_WAIT)
        end,

        onConnect = function(self)
            Log:write(Log.INFO, 'Connecting to master...')
        end,

        connect = function(self)
            if Net.ports['master'] then
                Log:write(Log.INFO, 'Connected to master on port:', Net.ports['master'])
                self:setState(PLANT_STATE.PAUSED)
            end
        end,

        onWorking = function(self)
            Log:write(Log.INFO, 'Starting production...')
            self:stop(false)
        end,

        working = function(self)
            for i=1, 3, 1 do
                -- local _, abs = GetLevel(Refinery.refs.buffer['hor' .. i][1])
                -- local cur, max = ScaleProduction(Refinery.refs.prod['hor' .. i], abs, maxBuffer)
                -- Refinery.stats.prod['hor' .. i]   = {cur = cur, max = max}
                -- Refinery.stats.buffer['hor' .. i] = {cur = abs, max = maxBuffer}

                -- Log:write(Log.DEBUG, 'HandleScaling() - Rubber  ' .. i .. ' - Buffer:', string.pad(math.round(abs, 2), 6, ' ', true), 'Production:', cur .. '/' .. max)
            end

            HandleExcessOil()
            HandleExcessResin()
        end,

        onPause = function(self)
            Log:write(Log.INFO, 'Pausing production...')
            self:stop(true)
        end,

        onDisconnect = function(self)
            Log:write(Log.INFO, 'Disconnecting from master...')
            self:stop(true)
        end,

        disconnect = function(self)
            if not Net.ports['master'] then
                Log:write(Log.INFO, 'Successfully disconnected')
                if self.reset then
                    self:setState(PLANT_STATE.SHUTDOWN)
                else
                    self:setState(PLANT_STATE.CONNECT_WAIT)
                end
            end
        end,

        onShutdown = function(self)
            local i = 3
            Log:write(Log.INFO, 'Rebooting plant in ' .. i ..'s')
            Schedule:add(i, computer.reset)
        end
    },
    {
        hor1   = 'Group_1 HOR',
        hor2   = 'Group_2 HOR',
        hor3   = 'Group_3 HOR',                             -- Grp #3 is only buffer
        resin1 = 'Group_1 Resin',
        resin2 = 'Group_2 Resin',
        coke   = 'Coke'
    },
    {
        pumpHOR  = 'Pump HOR',
        pumpCoke = 'Pump Coke',
        eStops   = {},
        resets   = {}
    }
)

for i, panel in ipairs(component.proxy(component.findComponent('Control'))) do
    local _, _, n = string.find(tostring(panel), '^MCP_(%d)Point')
    for x = 0, n - 1, 1 do
        local mod = panel:getModule(x, 0)
        if tostring(mod) == 'PushbuttonModule' then
            table.insert(Refinery.refs.misc.resets, mod)
            event:register(mod, 'Trigger', function ()
                Refinery.reset = true
                Refinery:setState(PLANT_STATE.DISCONNECT_WAIT)
            end)
        elseif tostring(mod) == 'MushroomPushbuttonModule' then
            table.insert(Refinery.refs.misc.eStops, mod)
            event:register(mod, 'Trigger', function ()
                -- toggle state
                Refinery.eStopped = not Refinery.eStopped
                Refinery:stop(Refinery.eStopped)

                -- update buttons
                for i, ref in pairs(Refinery.refs.misc.eStops) do
                    if Refinery.eStopped then
                        ref:setColor(Color('red', 0.8))
                    else
                        ref:setColor(Color('red', 0))
                    end
                end
            end)
        elseif tostring(mod) == 'IndicatorModule' then
            if not RcvLED then
                RcvLED = mod
            else
                SndLED = mod
            end
        end
    end
end

Net:addHandler('REQ_PLANT_STATUS', 'handleReqPlantStateRcv', function(self, srcUUID, machine, port)
    Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STATUS', 6 + 2)                 -- 4 prod lines, 5 buffer

    for n, data in pairs(Refinery.stats.prod) do
        Net:send(srcUUID, Net.ports.master, 'RSP_PR_STATE', n, n, data.cur, data.max)  -- what, mat, cur, max
    end

    for n, data in pairs(Refinery.stats.buffer) do
        Net:send(srcUUID, Net.ports.master, 'RSP_BU_STATE', n, n, data.cur, data.max)  -- what, mat, cur, max
    end
end)

Net:addHandler('REQ_PLANT_START', 'handleReqStartRcv', function(self, srcUUID, machine, port)
    if machine ~= 'master' then
        return
    end

    if Refinery.state == PLANT_STATE.WORKING then
        Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_START')
    elseif Refinery.state ~= PLANT_STATE.PAUSED then
        Net:send(srcUUID, Net.ports.master, 'NAK', 'REQ_PLANT_START')
    else
        Refinery:setState(PLANT_STATE.WORKING)
        Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_START')
    end
end)

Net:addHandler('REQ_PLANT_STOP', 'handleReqStopRcv',function(self, srcUUID, machine, port)
    if machine ~= 'master' then
        return
    end

    if Refinery.state == PLANT_STATE.PAUSED then
        Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STOP')
    elseif Refinery.state ~= PLANT_STATE.WORKING then
        Net:send(srcUUID, Net.ports.master, 'NAK', 'REQ_PLANT_STOP')
    else
        Refinery:setState(PLANT_STATE.PAUSED)
        Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STOP')
    end
end)

function HandleExcessOil()
    if Refinery.state ~= PLANT_STATE.WORKING then
        return
    end

    local level = GetLevel(--[[refs.buffer.coke?]])
    if     level > 0.3 and     Refinery.refs.prod.coke[1].standby and not Refinery.eStopped then
        Refinery.refs.prod.coke[1].standby = false
    elseif level < 0.1 and not Refinery.refs.prod.coke[1].standby then
        Refinery.refs.prod.coke[1].standby = true
    elseif level > 0.7 and     Refinery.refs.prod.coke[2].standby and not Refinery.eStopped then
        Refinery.refs.prod.coke[2].standby = false
    elseif level < 0.5 and not Refinery.refs.prod.coke[2].standby then
        Refinery.refs.prod.coke[2].standby = true
    end

    if level > 0.1 then
        Refinery.refs.misc.pump.coke.standby = false
    else
        Refinery.refs.misc.pump.coke.standby = true
    end
end

function HandleExcessResin()
    if Refinery.state ~= PLANT_STATE.WORKING then
        return
    end

    for i = 1, 2, 1 do
        local level = GetLevel(Refinery.refs.buffer['resin' .. i], QTY.ITEM_STACK)

        if level > 0.5 and not Refinery.refs.prod['resin' .. i].standby then
            Refinery.refs.prod['resin' .. i].standby = true
            Log:write(Log.INFO, 'Paused Resin Refinery Group #' .. i .. ' due to buffer level')
        elseif level < 0.2 and Refinery.refs.prod['resin' .. i].standby and not Refinery.eStopped then
            Refinery.refs.prod['resin' .. i].standby = false
            Log:write(Log.INFO, 'Enabled Resin Refinery Group #' .. i .. ' due to buffer level')
        end

    end
end


-- ----------
-- run
-- ----------

Log:write(Log.INFO, 'System started')

Net:init(Refinery.name, RcvLED, SndLED)

repeat
    event:update()

    Schedule:update(computer.millis())

    Refinery:update()

until false
