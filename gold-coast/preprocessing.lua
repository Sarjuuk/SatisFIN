 -- ----------
 -- load helper funcs
 -- ----------


Net.addHandler('REQ_ITEM', 'handleReqItemRcv', function(self, srcUUID, name, qty)

    Log:write(Log.DEBUG, 'Net:handleReqItemRcv() - ' .. srcUUID, name, qty)

    if name == 'Plastic' then
        local _, amt = GetLevel(Plant.refs.buffer.plastic, QTY.ITEM_STACK, name)
        if amt < (Preprocessing.request.plastic + qty) then
            Net:send(srcUUID, Net.ports.master, 'NAK', 'REQ_ITEM', 'Plastic', qty)
        else
            Preprocessing.request.plastic = Preprocessing.request.plastic + qty
            Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_ITEM', 'Plastic')
        end
    elseif name == 'Rubber' then
        local _, amt = GetLevel(Plant.refs.buffer.rubber, QTY.ITEM_STACK, name)
        if amt < (Preprocessing.request.rubber + qty) then
            Net:send(srcUUID, Net.ports.master, 'NAK', 'REQ_ITEM', 'Rubber', qty)
        else
            Preprocessing.request.rubber = Preprocessing.request.rubber + qty
            Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_ITEM', 'Rubber')
        end
    else
        Log:write(Log.warn, 'Net:handleReqItemRecv() - unknown item ' .. name .. ' requested')
    end
end)

Net.addHandler('REQ_PLANT_STATUS', 'handleReqPlantStateRcv',  function(self, srcUUID, name, qty)
    Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STATUS', 2 + 2)                 -- 2 prod lines, 2 buffer

    for n, data in pairs(Plant.stats.prod) do
        Net:send(srcUUID, Net.ports.master, 'RSP_PR_STATE', n, n, data.cur, data.max)  -- what, cur, max
    end

    for n, data in pairs(Plant.stats.buffer) do
        Net:send(srcUUID, Net.ports.master, 'RSP_BU_STATE', n, n, data.cur, data.max)  -- what, cur, max
    end
end)




-- ----------
-- init
-- ----------

Log:write(Log.INFO, 'System started')

blItr = 100
blDir = true

Preprocessing = Plant:init(
    {
        name        = 'preprocessing',
        request     = {rubber  = 0, plastic = 0},
        maxBuffer   = 500,
        canTransfer = false,

        onStartup = function(self)
            -- item.type empty for some reason
            event:register(self.refs.misc.merger, 'ItemOutputted', function (item)
                Preprocessing.canTransfer = true
            end)

            if self.refs.misc.merger:canOutput() then
                self.canTransfer = true
            end
        end,

        working = function(self)
            local _, abs = GetLevel(self.refs.buffer.plastic[1], QTY.ITEM_STACK, 'Plastic')
            local cur, max = ScaleProduction(self.refs.prod.plastic, abs, self.maxBuffer)
            self.stats.prod.plastic   = {cur = cur, max = max}
            self.stats.buffer.plastic = {cur = abs, max = self.maxBuffer}

            -- Log:write(Log.DEBUG, 'HandleScaling() - Plastic - Buffer:', string.pad(abs, 4, ' ', true), 'Production:', cur .. '/' .. max)

            local _, abs = GetLevel(self.refs.buffer.rubber[1], QTY.ITEM_STACK, 'Rubber')
            local cur, max = ScaleProduction(self.refs.prod.rubber, abs, self.maxBuffer)
            self.stats.prod.rubber   = {cur = cur, max = max}
            self.stats.buffer.rubber = {cur = abs, max = self.maxBuffer}

            -- Log:write(Log.DEBUG, 'HandleScaling() - Rubber  - Buffer:', string.pad(abs, 4, ' ', true), 'Production:', cur .. '/' .. max)

            self:handleOutput()
        end,

        handleOutput = function(self)
            local gate = self.refs.misc.merger

            if not gate.canOutput() or not self.canTransfer then
                return
            end

            local hasRubber  = gate:getInput(PORT.LEFT)
            local hasPlastic = gate:getInput(PORT.RIGHT)

            if self.request.rubber > self.request.plastic then
                if hasRubber and self.request.rubber > 0 then
                    gate:transferItem(PORT.LEFT)
                    self.canTransfer = false
                    self.request.rubber = self.request.rubber - 1
                    return
                end

                if hasPlastic and self.request.plastic > 0 then
                    gate:transferItem(PORT.RIGHT)
                    self.canTransfer = false
                    self.request.plastic = self.request.plastic - 1
                    return
                end
            else
                if hasPlastic and self.request.plastic > 0 then
                    gate:transferItem(PORT.RIGHT)
                    self.canTransfer = false
                    self.request.plastic = self.request.plastic - 1
                    return
                end

                if hasRubber and self.request.rubber > 0 then
                    gate:transferItem(PORT.LEFT)
                    self.canTransfer = false
                    self.request.rubber = self.request.rubber - 1
                    return
                end
            end
        end
    },
    {
        rubber  = 'Rubber',
        plastic = 'Plastic',
        water   = 'Water'
    },
    {
        lights = 'Merger',
        merger = 'Signal'
    }
)


Net:init(Plant.name)


-- ----------
-- run
-- ----------

repeat
    event:update()

    Schedule:update(computer.millis())

    Preprocessing:update()

    blink(Plant.refs.misc.lights, 5, 0, 1, 0)

until false
