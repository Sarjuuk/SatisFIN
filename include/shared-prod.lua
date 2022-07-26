--[[
    1: boot
    2: run
    3: shutdownWait
    4: shutdown
 ]]

State = PLANT_STATE.STARTUP

EStopped = false

StackSize = 200
WagonSize = StackSize * 32

function AllMachines(fn)
    for g = 1, 6, 1 do                                      -- group
        for s = 1, 3, 1 do                                  -- stage
            fn(g, s, Plant.refs.misc.byGroup[g][s])
        end
    end
end


Control = {
    lpOfFSet  = 12,
    lpGrpSize = 4,
    elements  = {                                           -- x, y, panelIdx
        eStop        = { 1, 1, 0},
        reset        = { 2, 4, 0},
        switch       = { 5, 1, nil},
        indicator    = { 5, 0, nil},
        display      = { 7, 1, nil},
        buffer11     = { 8, 7, 0},
        buffer12     = { 8, 8, 0},
        wagon1       = {10, 8, 0},
        buffer41     = { 5, 7, 0},
        buffer42     = { 5, 8, 0},
        wagon4       = { 7, 8, 0},
        NetIn        = { 9, 0, 0},
        NetOut       = {10, 0, 0},
        productivity = { 8, 4, 0}
    },

    updateBuffer = function(txt)
        for name, refs in pairs(Plant.refs.buffer) do
            local _, _, n = name:find('^%w+(%d)$')
            for i, ref in ipairs(refs) do
                local cur = txt
                if not txt then
                    _, cur = GetLevel(ref, StackSize)
                end
                Control:getPanelElement('buffer' .. n .. i, nil, nil, 1):setText(cur)
            end
            local nWagons = math.floor(Plant.stats.buffer[name].cur / WagonSize)
            if txt then
                nWagons = 0
            end
            Control:getPanelElement('wagon' .. n, nil, nil, 1):setText(nWagons)
        end
    end,

    updateProductivity = function(num)
        local ppm, base = 0, 60
        if not num then
            AllMachines(function(g, s, machines)
                if s ~= 3 then
                    return
                end

                for _, m in ipairs(machines) do
                    ppm = ppm + (base * m.productivity)
                end
            end)
        else
            ppm = num
        end

        Control:getPanelElement('productivity', nil, nil, 1):setText(ppm)
    end,

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

        if EStopped or not max or ((Plant.states[g][s] or 0) & 1) > 0 then
            el:setColor(Color('black'))
        elseif ((Plant.states[g][s] or 0) & 2) > 0 then
            el:setColor(Color('blue'))
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
            el:setColor(Color('red', 2))
        else
            el:setColor(Color('darkred', 0))
        end
    end,

    updateReset = function(el)
        if State == PLANT_STATE.STARTUP then
            el:setColor(0.5, 0.5, 0, 1)
        elseif State == PLANT_STATE.WORKING then
            el:setColor(0, 1, 0, 2)
        elseif State == PLANT_STATE.DISCONNECT_WAIT then
            el:setColor(1, 0.5, 0, 1)
        elseif State == PLANT_STATE.SHUTDOWN then
            el:setColor(Color('red'))
        else
            el:setColor(Color('black'))
        end
    end,

    toggleSwitch = function(this, grp, stg)
        local mask = Plant.states[grp][stg] or 0

        if this.state then
            mask = mask & ~1
        else
            mask = mask | 1
        end

        Plant.states[grp][stg] = mask

        Control.updateSwitch(this, grp, stg)
        Control.updateIndicator(nil, grp, stg)

        if EStopped then                            -- only allow toggle off
            return
        end

        PropagateState(grp, stg)
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
        self.updateBuffer('Booting...')

        -- train wagon indicator
        self.updateProductivity(0)

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
                                PropagateState(g, s)
                                Control.updateSwitch(nil, g, s)
                            end
                        end)

                    end, el))
                    self.updateMushroom(el)

                -- plc reset
                elseif tostring(el) == 'PushbuttonModule' then
                    table.insert(Plant.refs.misc.resets, el)
                    event:register(el, 'Trigger', function()
                        State = PLANT_STATE.DISCONNECT_WAIT
                        Schedule:add(2, computer.reset)
                    end)
                end
            end
        end
    end,

    getPanelElement = function(self, element, groupIdx, stageIdx, refPanelIdx)
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
        local ofFSet   = 0
        local panelIdx = self.elements[element][3]

        if groupIdx and groupIdx > 3 then
            panelIdx = 3 - (tonumber(groupIdx) - 3)
            panel    = Plant.refs.misc.panels[3]
            ofFSet   = self.lpOfFSet - (stageIdx * self.lpGrpSize)
        elseif groupIdx and groupIdx > 0 then
            panelIdx = 3 - tonumber(groupIdx)
            panel    = Plant.refs.misc.panels[2]
            ofFSet   = self.lpOfFSet - (stageIdx * self.lpGrpSize)
        elseif refPanelIdx > 0 and refPanelIdx < 4 then
            panel = Plant.refs.misc.panels[refPanelIdx]
        end

        if not panel then
            Log:write(Log.ERROR, 'Control:getPanelElement() - invalid panel ',refPanelIdx)
            return nil
        end

        -- Log:write(Log.DEBUG, 'Control:getPanelElement()', tostring(panel), 'x:', self.elements[element][1], 'y:', self.elements[element][2] ..  '+' .. ofFSet, panelIdx, element)

        return panel:getModule(self.elements[element][1], self.elements[element][2] + ofFSet, panelIdx)
    end,
}

function PropagateState(grp, stg)
    for _, ref in ipairs(Plant.refs.misc.byGroup[grp][stg]) do
        if EStopped then
            ref.standby = true
        elseif (Plant.states[grp][stg] or 0) > 0 then
            ref.standby = true
        else
            ref.standby = false
        end
    end
end

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
    Control.updateBuffer()
    Control.updateProductivity()
end

function HandleScaling()
    local _, absBuff, maxBuff = GetLevel(Plant.refs.buffer.machines1, StackSize)
    Plant.stats.buffer.machines1 = {cur = absBuff, max = maxBuff * 0.6}

    local cur, max = ScaleProduction({Plant.refs.prod.machines1, Plant.refs.prod.machines2, Plant.refs.prod.machines3}, absBuff, maxBuff * 0.6)
    for i, _ in pairs(cur) do
        Plant.stats.prod['machines' .. i]   = {cur = cur[i], max = max[i]}
        local mask = Plant.states[i][3] or 0
        if cur[i] > 0 then
            mask = mask & ~2
        else
            mask = mask | 2
        end
        Plant.states[i][3] = mask
    end

    -- Log:write(Log.DEBUG, 'HandleScaling() - Rubber 1-3 - Buffer:', string.pad(abs, 4, ' ', true), 'Production:', cur .. '/' .. max)

    local _, absBuff, maxBuff = GetLevel(Plant.refs.buffer.machines4, StackSize)
    Plant.stats.buffer.machines4 = {cur = absBuff, max = maxBuff * 0.6}


    local cur, max = ScaleProduction({Plant.refs.prod.machines4, Plant.refs.prod.machines5, Plant.refs.prod.machines6}, absBuff, maxBuff * 0.6)
    for i, _ in pairs(cur) do
        Plant.stats.prod['machines' .. (i + 3)]   = {cur = cur[i], max = max[i]}
        local mask = Plant.states[i + 3][3] or 0
        if cur[i] > 0 then
            mask = mask & ~2
        else
            mask = mask | 2
        end
        Plant.states[i + 3][3] = mask
    end

    -- Log:write(Log.DEBUG, 'HandleScaling() - Rubber 4-6 - Buffer:', string.pad(abs, 4, ' ', true), 'Production:', cur .. '/' .. max)

    AllMachines(function(g, s, m)
        PropagateState(g, s)
    end)
end
