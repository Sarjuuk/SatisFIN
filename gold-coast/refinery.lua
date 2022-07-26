-- -----------
-- vars
-- -----------

StackSize = 200                                             -- for resin


-- ----------
-- create refs
-- ----------

Plant = {
    name     = 'refinery',
    state    = PLANT_STATE.STARTUP,
    eStopped = false,

    refs = {
        prod = {
            hor1   = 'Machine Group_1 HOR',
            hor2   = 'Machine Group_2 HOR',
            resin1 = 'Machine Group_1 Resin',
            resin2 = 'Machine Group_2 Resin',
            coke   = 'Machine Coke'
        },
        buffer = {
            resin1 = 'Buffer Resin Group_1',
            resin2 = 'Buffer Resin Group_2',
            hor1   = 'Buffer HOR Group_1',
            hor2   = 'Buffer HOR Group_2',
            hor3   = 'Buffer HOR Group_3',
            coke   = 'Buffer Coke'
        },
        misc = {
            pumpHOR  = 'Pump HOR',
            pumpCoke = 'Pump Coke',
            panels   = {'Control Panel Main', 'Control EStopHolder'},
            eStops   = {},
            resets   = {},
            rcvLED   = nil,
            sndLED   = nil
        }
    },
    stats = {
        prod   = {                                          -- machines running per segment
            hor1   = {cur = 0, max = 0},
            hor2   = {cur = 0, max = 0},
            resin1 = {cur = 0, max = 0},
            resin2 = {cur = 0, max = 0},
            coke   = {cur = 0, max = 0}
        },
        buffer = {                                          -- buffer utilization
            hor1   = {cur = 0, max = 0},
            hor2   = {cur = 0, max = 0},
            hor3   = {cur = 0, max = 0},
            resin1 = {cur = 0, max = 0},
            resin2 = {cur = 0, max = 0},
            coke   = {cur = 0, max = 0}
        }
    },

    getRefs = function(self, sub)
        sub = sub or self.refs

        for k, val in pairs(sub) do
            if type(val) == 'table' then
                sub[k] = self:getRefs(val)
            else
                local uuids = component.findComponent(val)
                if string.find(val, 'Control')  then
                    uuids = uuids[1]
                end
                sub[k] = component.proxy(uuids)
            end
        end

        return sub
    end,

    halt = function(self, enable)
        if not enable and self.eStopped then
            return
        elseif (enable and self.state == PLANT_STATE.PAUSED) or (not enable and self.state == PLANT_STATE.WORKING) then
            return
        end

        for _, ref in pairs(self.refs) do
            if type(ref) == 'table' then
                for _, r in pairs(ref) do
                    r.standby = enable
                end
            else
                ref.standby = enable
            end
        end
    end
}

Plant:getRefs()

for i, panel in ipairs(Plant.refs.misc.panels) do
    local _, _, n = string.find(tostring(panel), '^MCP_(%d)Point')
    for x = 0, n - 1, 1 do
        local mod = panel:getModule(x, 0)
        if tostring(mod) == 'PushbuttonModule' then
            table.insert(Plant.refs.misc.resets, mod)
            event:register(mod, 'Trigger', function ()
                NOP() -- todo: implement reset
            end)
        elseif tostring(mod) == 'MushroomPushbuttonModule' then
            table.insert(Plant.refs.misc.eStops, mod)
            event:register(mod, 'Trigger', function ()
                -- toggle state
                Plant.eStopped = not Plant.eStopped

                -- update buttons
                for i, ref in pairs(Plant.refs.misc.eStops) do
                    if Plant.eStopped then
                        ref:setColor(Color('red', 0.8))
                    else
                        ref:setColor(Color('red', 0))
                    end
                end

                -- todo: move estop check somewhere else

                -- --  update machines
                -- for i, tbl in pairs(HorRef) do
                --     for j, ref in pairs(tbl) do
                --         ref.standby = Plant.eStopped
                --     end
                -- end

                -- for i, ref in pairs(ResinRef) do
                --     ref.standby = Plant.eStopped
                -- end

                -- for i, ref in pairs(Plant.refs.prod.coke) do
                --     ref.standby = Plant.eStopped
                -- end

                -- ExcessPump.standby = Plant.eStopped
            end)
        elseif tostring(mod) == 'IndicatorModule' then
            if not Plant.refs.misc.rcvLED then
                Plant.refs.misc.rcvLED = mod
            else
                Plant.refs.misc.sndLED = mod
            end
        end
    end
end

Net.msg.REQ_PLANT_STATUS[1] = 'handleReqPlantStateRcv'
Net[Net.msg.REQ_PLANT_STATUS[1]] = function(self, srcUUID, name, qty)
    Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STATUS', 6 + 2)                 -- 4 prod lines, 5 buffer

    for n, data in pairs(Plant.stats.prod) do
        Net:send(srcUUID, Net.ports.master, 'RSP_PR_STATE', n, n, data.cur, data.max)  -- what, mat, cur, max
    end

    for n, data in pairs(Plant.stats.buffer) do
        Net:send(srcUUID, Net.ports.master, 'RSP_BU_STATE', n, n, data.cur, data.max)  -- what, mat, cur, max
    end
end



function HandleExcessOil()
    local level = GetLevel(ExcessTank)
    if     level > 0.3 and     Plant.refs.prod.coke[1].standby then
        Plant.refs.prod.coke[1].standby = false
    elseif level < 0.1 and not Plant.refs.prod.coke[1].standby then
        Plant.refs.prod.coke[1].standby = true
    elseif level > 0.7 and     Plant.refs.prod.coke[2].standby then
        Plant.refs.prod.coke[2].standby = false
    elseif level < 0.5 and not Plant.refs.prod.coke[2].standby then
        Plant.refs.prod.coke[2].standby = true
    end

    if level > 0.1 then
        ExcessPump.standby = false
    else
        ExcessPump.standby = true
    end
end

function HandleExcessResin()
    -- inv:getStack(slotIdx)

    for i, ref in pairs(ResinBox) do
        local level = GetLevel(ref, StackSize)

        if level > 0.5 and not ResinRef[i].standby then
             ResinRef[i].standby = true
         elseif level < 0.2 and ResinRef[i].standby then
            ResinRef[i].standby = false
        end

        Log:write(Log.INFO, 'ResinBox ' .. i .. ': ' .. math.round(level * 100, 2) .. '% - Prod. Enabled: ' .. tostring(not ResinRef[i].standby))
    end
end


Log:write(Log.INFO, 'System started')


-- ----------
-- init
-- ----------

Net:init(Plant.name, Plant.refs.misc.rcvLED, Plant.refs.misc.sndLED)


-- ----------
-- run
-- ----------

repeat
    event:update()

    Schedule:update(computer.millis())

    if Plant.eStopped then
        goto continue
    end

    -- burn excess hor
    -- HandleExcessOil()

    -- throttle resin refineries on demand
    -- HandleExcessResin()

    ::continue::                                            -- fucking hell!

until false
