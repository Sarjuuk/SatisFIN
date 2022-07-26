Net.msg.REQ_PLANT_STATUS[1] = 'handleReqPlantStateRcv'
Net[Net.msg.REQ_PLANT_STATUS[1]] = function(self, srcUUID, name, qty)
    Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STATUS', 6 + 1 + 6) -- prod lines + water prod + buffer

    for n, data in pairs(Plant.stats.prod) do
        Net:send(srcUUID, Net.ports.master, 'RSP_PR_STATE', n, 'fuel', data.cur, data.max) --  what, cur, max
    end

    for n, data in pairs(Plant.stats.buffer) do
        Net:send(srcUUID, Net.ports.master, 'RSP_BU_STATE', n, 'fuel', data.cur, data.max) --  what, cur, max
    end
end

function HandleScaling()
    local maxBuffer = 400 -- small tank

    for i=1, 3, 1 do
        local _, abs = GetLevel(Plant.refs.buffer['rubber' .. i][1])
        local cur, max = ScaleProduction(Plant.refs.prod['rubber' .. i], abs, maxBuffer)
        Plant.stats.prod['rubber' .. i]   = {cur = cur, max = max}
        Plant.stats.buffer['rubber' .. i] = {cur = abs, max = maxBuffer}

        -- Log:write(Log.DEBUG, 'HandleScaling() - Rubber  ' .. i .. ' - Buffer:', string.pad(math.round(abs, 2), 6, ' ', true), 'Production:', cur .. '/' .. max)

        local _, abs = GetLevel(Plant.refs.buffer['plastic' .. i][1])
        local cur, max = ScaleProduction(Plant.refs.prod['plastic' .. i], abs, maxBuffer)
        Plant.stats.prod['plastic' .. i]   = {cur = cur, max = max}
        Plant.stats.buffer['plastic' .. i] = {cur = abs, max = maxBuffer}

       --  Log:write(Log.DEBUG, 'HandleScaling() - Plastic ' .. i .. ' - Buffer:', string.pad(math.round(abs, 2), 6, ' ', true), 'Production:', cur .. '/' .. max)
    end
end



-- ----------
-- init
-- ----------

Log:write(Log.INFO, 'System started')

blItr = 100
blDir = true

local rm1, rm2, rm3, pm1, pm2, pm3, rb1, rb2, rb3, pb1, pb2, pb3, rp1, rp2, rp3, pp1, pp2, pp3, s = component.findComponent(
        'Rubber Machine Group1', 'Rubber Machine Group2', 'Rubber Machine Group3', 'Plastic Machine Group1', 'Plastic Machine Group2', 'Plastic Machine Group3',
        'Rubber Buffer 1',       'Rubber Buffer 2',       'Rubber Buffer 3',       'Plastic Buffer 1',       'Plastic Buffer 2',       'Plastic Buffer 3',
        'Rubber Pump 1',         'Rubber Pump 2',         'Rubber Pump 3',         'Plastic Pump 1',         'Plastic Pump 2',         'Plastic Pump 3', 'Signal')
Plant = {
    name = 'fuelPlant',
    refs = {
        prod = {
            rubber1  = component.proxy(rm1),
            rubber2  = component.proxy(rm2),
            rubber3  = component.proxy(rm3),
            plastic1 = component.proxy(pm1),
            plastic2 = component.proxy(pm2),
            plastic3 = component.proxy(pm3),
            water    = {} -- maybe later
        },
        buffer = {
            rubber1  = component.proxy(rb1),
            rubber2  = component.proxy(rb2),
            rubber3  = component.proxy(rb3),
            plastic1 = component.proxy(pb1),
            plastic2 = component.proxy(pb2),
            plastic3 = component.proxy(pb3)
        },
        misc = {
            pumpR1 = component.proxy(rp1),
            pumpR2 = component.proxy(rp2),
            pumpR3 = component.proxy(rp3),
            pumpP1 = component.proxy(pp1),
            pumpP2 = component.proxy(pp2),
            pumpP3 = component.proxy(pp3),
            lights = component.proxy(s),
        }
    },
    stats = {
        prod = {                                            -- machines running per segment
            rubber1  = {cur = 0, max = 0},
            rubber2  = {cur = 0, max = 0},
            rubber3  = {cur = 0, max = 0},
            plastic1 = {cur = 0, max = 0},
            plastic2 = {cur = 0, max = 0},
            plastic3 = {cur = 0, max = 0},
            water    = {cur = 0, max = 0}
        },
        buffer = {                                          -- buffer utilization
            rubber1  = {cur = 0, max = 0},
            rubber2  = {cur = 0, max = 0},
            rubber3  = {cur = 0, max = 0},
            plastic1 = {cur = 0, max = 0},
            plastic2 = {cur = 0, max = 0},
            plastic3 = {cur = 0, max = 0}
        }
    }
}

Net:init(Plant.name)


repeat
    event:update()

    Schedule:update(computer.millis())

    HandleScaling()

until false
