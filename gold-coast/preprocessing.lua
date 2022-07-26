StackSize = 200

 -- ----------
 -- load helper funcs
 -- ----------

function blink(lights, speed, red, green, blue)

    if (blDir) then
        blItr = blItr + speed
    else
        blItr = blItr - speed
    end

    if (blDir and blItr >= 100) then
        blDir = false
    elseif (not blDir and blItr <= 0) then
        blDir = true
    end

    local c = {
        r = red   * blItr / 255,
        g = green * blItr / 255,
        b = blue  * blItr / 255
    }

    for _, light in pairs(lights) do
        local lightData = light:getPrefabSignData()
        lightData.background = c
        light:setPrefabSignData(lightData)
    end

end

Net.msg.REQ_ITEM[1] = 'handleReqItemRcv'
Net[Net.msg.REQ_ITEM[1]] = function(self, srcUUID, name, qty)

    Log:write(Log.DEBUG, 'Net:handleReqItemRcv() - ' .. srcUUID, name, qty)

    if name == 'Plastic' then
        local _, amt = GetLevel(Plant.refs.buffer.plastic, StackSize, name)
        if amt < (ReqPlastic + qty) then
            Net:send(srcUUID, Net.ports.master, 'NAK', 'REQ_ITEM', 'Plastic', qty)
        else
            ReqPlastic = ReqPlastic + qty
            Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_ITEM', 'Plastic')
        end
    elseif name == 'Rubber' then
        local _, amt = GetLevel(Plant.refs.buffer.rubber, StackSize, name)
        if amt < (ReqRubber + qty) then
            Net:send(srcUUID, Net.ports.master, 'NAK', 'REQ_ITEM', 'Rubber', qty)
        else
            ReqRubber = ReqRubber + qty
            Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_ITEM', 'Rubber')
        end
    else
        Log:write(Log.warn, 'Net:handleReqItemRecv() - unknown item ' .. name .. ' requested')
    end
end

Net.msg.REQ_PLANT_STATUS[1] = 'handleReqPlantStateRcv'
Net[Net.msg.REQ_PLANT_STATUS[1]] = function(self, srcUUID, name, qty)
    Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STATUS', 2 + 2)                 -- 2 prod lines, 2 buffer

    for n, data in pairs(Plant.stats.prod) do
        Net:send(srcUUID, Net.ports.master, 'RSP_PR_STATE', n, n, data.cur, data.max)  -- what, cur, max
    end

    for n, data in pairs(Plant.stats.buffer) do
        Net:send(srcUUID, Net.ports.master, 'RSP_BU_STATE', n, n, data.cur, data.max)  -- what, cur, max
    end
end

function HandleScaling()
    local maxBuffer = 500

    local _, abs = GetLevel(Plant.refs.buffer.plastic[1], StackSize, 'Plastic')
    local cur, max = ScaleProduction(Plant.refs.prod.plastic, abs, maxBuffer)
    Plant.stats.prod.plastic   = {cur = cur, max = max}
    Plant.stats.buffer.plastic = {cur = abs, max = maxBuffer}

    -- Log:write(Log.DEBUG, 'HandleScaling() - Plastic - Buffer:', string.pad(abs, 4, ' ', true), 'Production:', cur .. '/' .. max)

    local _, abs = GetLevel(Plant.refs.buffer.rubber[1], StackSize, 'Rubber')
    local cur, max = ScaleProduction(Plant.refs.prod.rubber, abs, maxBuffer)
    Plant.stats.prod.rubber   = {cur = cur, max = max}
    Plant.stats.buffer.rubber = {cur = abs, max = maxBuffer}

    -- Log:write(Log.DEBUG, 'HandleScaling() - Rubber  - Buffer:', string.pad(abs, 4, ' ', true), 'Production:', cur .. '/' .. max)
end


function HandleOutput()
    local merger = Plant.refs.misc.merger

    if not merger.canOutput then
        return
    end
    local hasRubber  = merger:getInput(PORT.LEFT)
    local hasPlastic = merger:getInput(PORT.RIGHT)

    if ReqRubber > ReqPlastic then
        if hasRubber and ReqRubber > 0 then
            merger:transferItem(PORT.LEFT)
            ReqRubber = ReqRubber - 1
            return
        end

        if hasPlastic and ReqPlastic > 0 then
            merger:transferItem(PORT.RIGHT)
            ReqPlastic = ReqPlastic - 1
            return
        end
    else
        if hasPlastic and ReqPlastic > 0 then
            merger:transferItem(PORT.RIGHT)
            ReqPlastic = ReqPlastic - 1
            return
        end

        if hasRubber and ReqRubber > 0 then
            merger:transferItem(PORT.LEFT)
            ReqRubber = ReqRubber - 1
            return
        end
    end
end


-- ----------
-- init
-- ----------

Log:write(Log.INFO, 'System started')

blItr = 100
blDir = true

ReqRubber  = 0
ReqPlastic = 0

local rm, pm, rb, pb, m, s = component.findComponent('Rubber Machine', 'Plastic Machine', 'Rubber Buffer', 'Plastic Buffer', 'Merger', 'Signal')
Plant = {
    name = 'preprocessing',
    refs = {
        prod = {
            rubber  = component.proxy(rm),
            plastic = component.proxy(pm),
            water   = {} -- maybe later
        },
        buffer = {
            rubber  = component.proxy(rb),
            plastic = component.proxy(pb)
        },
        misc = {
            lights = component.proxy(s),
            merger = component.proxy(m[1])
        }
    },
    stats = {
        prod   = {                                          -- machines running per segment
            rubber  = {cur = 0, max = 0},
            plastic = {cur = 0, max = 0},
         -- water   = {cur = 0, max = 0}
        },
        buffer = {                                          -- buffer utilization
            rubber  = {cur = 0, max = 0},
            plastic = {cur = 0, max = 0}
        }
    }
}


Net:init(Plant.name)

-- item.type empty for some reason .. use workaround
--[[
event:register(Merger, 'ItemOutputted', function (item)
    if item.type.name == 'Rubber' then
        ReqRubber = ReqRubber - 1
    elseif item.type.name == 'Plastic' then
        ReqPlastic = ReqPlastic - 1
    end
end)
  ]]
--[[
event:register(Merger, 'ItemRequest', function (port, item)
    print('EvSplitterIn', item, port)
end)
  ]]

-- ----------
-- run
-- ----------

repeat
    event:update()

    Schedule:update(computer.millis())

    HandleScaling()

    HandleOutput()

   blink(Plant.refs.misc.lights, 5, 0, 1, 0)

until false
