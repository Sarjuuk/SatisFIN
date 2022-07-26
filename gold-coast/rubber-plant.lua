Plant = {
    name = 'rubberPlant',
    refs = {
        prod = {
            machines1 = 'Machine Group_1 Stage_3',
            machines2 = 'Machine Group_2 Stage_3',
            machines3 = 'Machine Group_3 Stage_3',
            machines4 = 'Machine Group_4 Stage_3',
            machines5 = 'Machine Group_5 Stage_3',
            machines6 = 'Machine Group_6 Stage_3',
        },
        buffer = {
            machines1 = 'Buffer Group_1-3',
            machines4 = 'Buffer Group_4-6'
        },
        misc = {
            panels  = {'Control Panel Main', 'Control Panel Group_1-3', 'Control Panel Group_4-6'},
            eStops  = {},
            resets  = {},
            byGroup = {
                {'Machine Group_1 Stage_1', 'Machine Group_1 Stage_2', 'Machine Group_1 Stage_3'},
                {'Machine Group_2 Stage_1', 'Machine Group_2 Stage_2', 'Machine Group_2 Stage_3'},
                {'Machine Group_3 Stage_1', 'Machine Group_3 Stage_2', 'Machine Group_3 Stage_3'},
                {'Machine Group_4 Stage_1', 'Machine Group_4 Stage_2', 'Machine Group_4 Stage_3'},
                {'Machine Group_5 Stage_1', 'Machine Group_5 Stage_2', 'Machine Group_5 Stage_3'},
                {'Machine Group_6 Stage_1', 'Machine Group_6 Stage_2', 'Machine Group_6 Stage_3'}
            }
        }
    },
    stats = {
        prod   = {                                          -- machines running per segment
            machines1 = {cur = 0, max = 0},
            machines2 = {cur = 0, max = 0},
            machines3 = {cur = 0, max = 0},
            machines4 = {cur = 0, max = 0},
            machines5 = {cur = 0, max = 0},
            machines6 = {cur = 0, max = 0}
        },
        buffer = {                                          -- buffer utilization
            machines1 = {cur = 0, max = 0},
            machines4 = {cur = 0, max = 0}
        }
    },
    states = {{}, {}, {}, {}, {}, {}, {}, {}, {}},          -- standby per group+stage( b1: manual switch, b2: auto scaling)

    getRefs = function(self, sub)
        sub = sub or self.refs

        for k, val in pairs(sub) do
            if type(val) == 'table' then
                sub[k] = self:getRefs(val)
            else
                local uuids = component.findComponent(val)
                if string.find(val, 'Panel')  then
                    uuids = uuids[1]
                end
                sub[k] = component.proxy(uuids)
            end
        end

        return sub
    end
}

Net.msg.REQ_PLANT_STATUS[1] = 'handleReqPlantStateRcv'
Net[Net.msg.REQ_PLANT_STATUS[1]] = function(self, srcUUID, name, qty)
    Net:send(srcUUID, Net.ports.master, 'ACK', 'REQ_PLANT_STATUS', 6 + 2)                 -- 6 prod lines, 2 buffer

    for n, data in pairs(Plant.stats.prod) do
        Net:send(srcUUID, Net.ports.master, 'RSP_PR_STATE', n, 'rubber', data.cur, data.max)  -- what, mat, cur, max
    end

    for n, data in pairs(Plant.stats.buffer) do
        Net:send(srcUUID, Net.ports.master, 'RSP_BU_STATE', n, 'rubber', data.cur, data.max)  -- what, mat, cur, max
    end
end

Plant:getRefs()

Log:start()

Log:write(Log.INFO, 'System started')

Control:init()

Net:init(Plant.name, Control:getPanelElement('NetIn', nil, nil, 1), Control:getPanelElement('NetOut', nil, nil, 1))

repeat
    event:update()

    Schedule:update(computer.millis())

    UpdateDisplays()

    HandleScaling()

    for _, ref in ipairs(Plant.refs.misc.resets) do
        Control.updateReset(ref)
    end

until false

