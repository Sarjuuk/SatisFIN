ExtFiles  = {
    '/include/utils.lua',
    '/include/network.lua',
    '/include/event.lua',
    '/include/scheduler.lua',
    '/include/logger.lua'
}

PlantName = 'rubberPlant'

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

--[[
    1: boot
    2: run
    3: shutdownWait
    4: shutdown
 ]]

State = 1

EStopped = false

function AllMachines(fn)
    for g = 1, 6, 1 do                                      -- group
        for s = 1, 3, 1 do                                  -- stage
            fn(g, s, Plant.refs.misc.byGroup[g][s])
        end
    end
end


Control = {
    lpOffset  = 12,
    lpGrpSize = 4,
    elements  = {                                           -- x, y, panelIdx
        eStop     = {1, 1, 0},
        reset     = {2, 4, 0},
        switch    = {5, 1, nil},
        indicator = {5, 0, nil},
        display   = {7, 1, nil}
    },

    updateSwitch = function(el, g, s)
        el = el or Control:getPanelElement('switch', g, s)

        if el.state and not EStopped then
            el:setColor(Color('white'))
        else
            el:setColor(Color('black'))
        end
    end,

    updateIndicator = function(el, g, s, cur, max)
        el = el or Control:getPanelElement('indicator', g, s)

        if EStopped or not max or not Plant.states[g][s] then
            el:setColor(Color('black'))
        elseif cur == max then
            el:setColor(Color('green'))
        elseif cur > 0 then
            el:setColor(Color('yellow'))
        else
            el:setColor(Color('red'))
        end
    end,

    updateMushroom = function(el)
        if EStopped then
            el:setColor(Color('red'))
        else
            el:setColor(Color('darkred', 0))
        end
    end,

    updateReset = function(el)
        if State == 1 then
            el:setColor(0.5, 0.5, 0, 1)
        elseif State == 2 then
            el:setColor(0, 1, 0, 2)
        elseif State == 3 then
            el:setColor(1, 0.5, 0, 1)
        elseif State == 4 then
            el:setColor(Color('red'))
        else
            el:setColor(Color('black'))
        end
    end,

    toggleSwitch = function(this, grp, stg)
        Plant.states[grp][stg] = this.state

        Control.updateSwitch(this, grp, stg)
        Control.updateIndicator(nil, grp, stg)

        if EStopped then                            -- only allow toggle off
            return
        end

        for _, ref in ipairs(Plant.refs.misc.byGroup[grp][stg]) do
            ref.standby = not this.state
        end
    end,

    init = function (self)
        AllMachines(function(g, s, machines)
            -- on/off switch
            local el = self:getPanelElement('switch', g, s)
            event:register(el, 'ChangeState', Bind(self.toggleSwitch, el, g, s))
            self.toggleSwitch(el, g, s)

            -- status indicator
            local el = self:getPanelElement('indicator', g, s)
            self.updateIndicator(el, g, s)

            -- text display
            local el = self:getPanelElement('display', g, s)
            el.monospace = true
            el.size = 36
            el.text = 'Booting...'
        end)

        -- buffer displays
        -- todo

        -- train wagon indicator
        -- todo

        for i, panelRef in ipairs(Plant.refs.misc.panels) do
            for j, el in ipairs (panelRef:getModules()) do
                 -- eStops
                 if tostring(el) == 'MushroomPushbuttonModule' then
                    table.insert(Plant.refs.misc.eStops, el)
                    event:register(el, 'Trigger', Bind(function(this)
                        EStopped = not EStopped

                        for _, ref in ipairs(Plant.refs.misc.eStops) do
                            Control.updateMushroom(ref)
                        end

                        AllMachines(function (g, s, machines)
                            for _, ref in ipairs(machines) do
                                if EStopped then
                                    ref.standby = true
                                elseif Plant.states[g][s] and not EStopped then
                                    ref.standby = false
                                end
                                Control.updateSwitch(nil, g, s)
                            end
                        end)

                    end, el))
                    self.updateMushroom(el)

                -- plc reset
                elseif tostring(el) == 'PushbuttonModule' then
                    table.insert(Plant.refs.misc.resets, el)
                    event:register(el, 'Trigger', function()
                        State = 3
                        Schedule:add(2, computer.reset)
                    end)
                end
            end
        end
    end,

    getPanelElement = function(self, element, groupIdx, stageIdx, refPanel)
        if stageIdx ~= nil and (stageIdx > 3 or stageIdx < 1) then
            Log:write(Log.ERROR, 'Control:getPanelElement() - invalid stageIdx ' .. stageIdx)
            return nil
        end

        if groupIdx ~= nil and (groupIdx > 6 or groupIdx < 1) then
            Log:write(Log.ERROR, 'Control:getPanelElement() - invalid groupIdx ' .. groupIdx)
            return nil
        end

        if not self.elements[element] then
            Log:write(Log.ERROR, 'Control:getPanelElement() - invalid element ' .. element)
            return nil
        end

        local panel    = nil
        local offset   = 0
        local panelIdx = self.elements[element][3] or (3 - tonumber(stageIdx))

        if groupIdx > 3 then
            panel  = Plant.refs.misc.panels[3]
            offset = (2 * self.lpOffset) - (groupIdx * self.lpGrpSize)
        elseif groupIdx > 0 then
            panel  = Plant.refs.misc.panels[2]
            offset = self.lpOffset - (groupIdx * self.lpGrpSize)
        elseif refPanel then
            panel  = refPanel
        end

        -- Log:write(Log.DEBUG, 'Control:getPanelElement()', self.elements[element][1], self.elements[element][2] ..  '+' .. offset, '3-' .. stageIdx, element, groupIdx)

        return panel:getModule(self.elements[element][1], self.elements[element][2] + offset, panelIdx)
    end,
}

function GetDisplayString(machine)
    local in1 = machine:getInputInv():getStack(0)
    local in2 = machine:getInputInv():getStack(1)
    local out = machine:getOutputInv():getStack(0)

    local fuel   = 0
    local solid  = 0
    local result = out.count
    local prod   = math.ceil(machine.productivity * 100) .. '%'

    if machine.standby then
        prod = 'off'
    end

    if in1.type and in1.type.form == 2 then -- form: 2 => liquid
        fuel  = math.round(in1.count / 1000, 1)
        solid = in2.count
    else
        fuel  = math.round(in2.count / 1000, 1)
        solid = in1.count
    end

    return string.pad(fuel, 4, ' ', true) .. string.pad(solid, 6, ' ', true) .. string.pad(prod, 6, ' ', true) .. string.pad(result, 5, ' ', true)
end


Plant = {
    refs = {
        prod = {
            rubber1  = 'Machine Group_1 Stage_3',
            rubber2  = 'Machine Group_2 Stage_3',
            rubber3  = 'Machine Group_3 Stage_3',
            rubber4  = 'Machine Group_4 Stage_3',
            rubber5  = 'Machine Group_5 Stage_3',
            rubber6  = 'Machine Group_6 Stage_3',
        },
        buffer = {
            rubber13 = 'Buffer Group_1-3',
            rubber46 = 'Buffer Group_4-6'
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
            rubber1 = {cur = 0, max = 0},
            rubber2 = {cur = 0, max = 0},
            rubber3 = {cur = 0, max = 0},
            rubber4 = {cur = 0, max = 0},
            rubber5 = {cur = 0, max = 0},
            rubber6 = {cur = 0, max = 0}
        },
        buffer = {                                          -- buffer utilization
            rubber13 = {cur = 0, max = 0},
            rubber46 = {cur = 0, max = 0}
        }
    },
    states = {{}, {}, {}, {}, {}, {}, {}, {}, {}},          -- manual standby per group+stage

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

Plant:getRefs()

function UpdateDisplays()
    AllMachines(function(g, s, machines)
        local text = ''
        local ln = "\n"
        local nActive = 0
        for i = 1, 3 - #machines , 1 do
            ln = ln .. ln
        end
        for i, ref in ipairs(machines) do
            text = text .. GetDisplayString(ref) .. ln
            if not ref.standby and ref.productivity > 0.2 then
                nActive = nActive + 1
            end
        end

        Control:getPanelElement('display', g, s).text = text
        Control.updateIndicator(nil, g, s, nActive, #machines)
    end)
end


Log:start()

Log:write(Log.INFO, 'System started')

Control:init()

Net:init(PlantName)

repeat
    event:update()

    Schedule:update(computer.millis())

    UpdateDisplays()

    for _, ref in ipairs(Plant.refs.misc.resets) do
        Control.updateReset(ref)
    end

until false


