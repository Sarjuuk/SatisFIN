ExtFiles  = {
    '/include/utils.lua',
    '/include/network.lua',
    '/include/event.lua',
    '/include/scheduler.lua',
    '/include/logger.lua'
}

PlantName = 'preprocessing'

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

function blink(self, lights, speed, red, green, blue)

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

    c = {
        r = red   * blItr / 255,
        g = green * blItr / 255,
        b = blue  * blItr / 255
    }

    for _, light in pairs(lights) do
        lightData = light:getPrefabSignData()
        lightData.background = c
        light:setPrefabSignData(lightData)
    end

end

Net.msg.REQ_ITEM[1] = 'handleReqItemRcv'
Net[Net.msg.REQ_ITEM[1]] = function(self, srcUUID, name, qty)

    Log:write(Log.DEBUG, 'Net:handleReqItemRcv() - ' .. srcUUID, name, qty)

    if name == 'Plastic' then
        local _, amt = GetLevel(Plant.refs.buffer.plastic, 200)
        if amt < (ReqPlastic + qty) then
            Net:send(srcUUID, Net.ports.master, 'NAK', 'REQ_ITEM', 'Plastic', qty)
        else
            ReqPlastic = ReqPlastic + qty
            Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_ITEM', 'Plastic')
        end
    elseif name == 'Rubber' then
        local _, amt = GetLevel(Plant.refs.buffer.rubber, 200)
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

Net.msg.REQ_STATUS[1] = 'handleReqPlantStateRcv'
Net[Net.msg.REQ_STATUS[1]] = function(self, srcUUID, name, qty)
    Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_STATUS', 2 + 2)                 -- 2 prod lines, 2 buffer

    for n, data in pairs(Plant.stats.prod) do
        Net:send(srcUUID, Net.ports.master, 'RSP_PR_STATE', n, data.cur, data.max)  -- what, cur, max
    end

    for n, data in pairs(Plant.stats.buffer) do
        Net:send(srcUUID, Net.ports.master, 'RSP_BU_STATE', n, data.cur, data.max)  -- what, cur, max
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
    -- Inputs
    -- 0 - Rubber
    -- 1 - None
    -- 2 - Plastic

    local merger = Plant.refs.misc.merger

    if not merger.canOutput then
        return
    end

    if ReqRubber > ReqPlastic and ReqRubber > 0 then
        local item = merger:getInput(0)
        if item then
            merger:transferItem(0)
            ReqRubber = ReqRubber - 1
            return
        end

        local item = merger:getInput(2)
        if item then
            merger:transferItem(2)
            ReqPlastic = ReqPlastic - 1
            return
        end
    elseif ReqPlastic > 0 then
        local item = merger:getInput(2)
        if item then
            merger:transferItem(2)
            ReqPlastic = ReqPlastic - 1
            return
        end

        local item = merger:getInput(0)
        if item then
            merger:transferItem(0)
            ReqRubber = ReqRubber - 1
            return
        end
    end
end

function EvMergerOut(item)
    if item.type.name == 'Rubber' then
        ReqRubber = ReqRubber - 1
    elseif item.type.name == 'Plastic' then
        ReqPlastic = ReqPlastic - 1
    end
end

function EvMergerIn(port, item)
    print('EvSplitterIn', item, port)
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
            water   = {cur = 0, max = 0}
        },
        buffer = {                                          -- buffer utilization
            rubber  = {cur = 0, max = 0},
            plastic = {cur = 0, max = 0}
        }
    }
}


Net:init(PlantName)

-- item.type empty for some reason .. use workaround
-- event:register(Merger, {EvMergerOut}, 'ItemOutputted')
-- event:register(Merger, {EvMergerIn}, 'ItemRequest')


-- ----------
-- run
-- ----------

repeat
    event:update()

    Schedule:update(computer.millis())

    HandleScaling()

    HandleOutput()

   -- blink(Plant.refs.misc.lights, 5, 0, 1, 0)

until false
