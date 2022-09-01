-- -----------
-- vars
-- -----------

blItr = 100
blDir = true

RcvLED, SndLED = nil, nil

FuelPlant = Plant:init(
    {
        name  = 'fuelPlant',
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
                local _, abs = GetLevel(FuelPlant.refs.buffer['rubber' .. i][1])
                local cur, max = ScaleProduction(FuelPlant.refs.prod['rubber' .. i], abs, QTY.FLUID_BUFFER_SMALL)
                FuelPlant.stats.prod['rubber' .. i]   = {cur = cur, max = max}
                FuelPlant.stats.buffer['rubber' .. i] = {cur = abs, max = QTY.FLUID_BUFFER_SMALL}

                -- Log:write(Log.DEBUG, 'HandleScaling() - Rubber  ' .. i .. ' - Buffer:', string.pad(math.round(abs, 2), 6, ' ', true), 'Production:', cur .. '/' .. max)

                local _, abs = GetLevel(FuelPlant.refs.buffer['plastic' .. i][1])
                local cur, max = ScaleProduction(FuelPlant.refs.prod['plastic' .. i], abs, QTY.FLUID_BUFFER_SMALL)
                FuelPlant.stats.prod['plastic' .. i]   = {cur = cur, max = max}
                FuelPlant.stats.buffer['plastic' .. i] = {cur = abs, max = QTY.FLUID_BUFFER_SMALL}

               --  Log:write(Log.DEBUG, 'HandleScaling() - Plastic ' .. i .. ' - Buffer:', string.pad(math.round(abs, 2), 6, ' ', true), 'Production:', cur .. '/' .. max)
            end
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
        rubber1  = 'Rubber Group1',
        rubber2  = 'Rubber Group2',
        rubber3  = 'Rubber Group3',
        plastic1 = 'Plastic Group1',
        plastic2 = 'Plastic Group2',
        plastic3 = 'Plastic Group3',
        water    = 'Water Extractor' -- maybe later
    },
    {
        pumpR1 = 'Rubber Pump Group1',
        pumpR2 = 'Rubber Pump Group2',
        pumpR3 = 'Rubber Pump Group3',
        pumpP1 = 'Plastic Pump Group1',
        pumpP2 = 'Plastic Pump Group2',
        pumpP3 = 'Plastic Pump Group3',
        lights = 'Stacklight'
    }
)



Net:addHandler('REQ_PLANT_STATUS', 'handleReqPlantStateRcv', function(self, srcUUID, name, qty)
    Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STATUS', 6 + 1 + 6) -- prod lines + water prod + buffer

    for n, data in pairs(FuelPlant.stats.prod) do
        Net:send(srcUUID, Net.ports.master, 'RSP_PR_STATE', n, 'fuel', data.cur, data.max) --  what, cur, max
    end

    for n, data in pairs(FuelPlant.stats.buffer) do
        Net:send(srcUUID, Net.ports.master, 'RSP_BU_STATE', n, 'fuel', data.cur, data.max) --  what, cur, max
    end
end)


-- ----------
-- init
-- ----------

Log:write(Log.INFO, 'System started')

Net:init(FuelPlant.name, SndLED, RcvLED)

repeat
    event:update()

    Schedule:update(computer.millis())

    FuelPlant:update()

until false
