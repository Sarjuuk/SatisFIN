Stacklight = {
    refs = {},
    new = function(self, refs, opts)
        opts = opts or {}

        if type(refs) == 'string' then
            local r = component.proxy(refs)
            if tostring(r) == 'name-of-signal-base' then
                table.insert(self.refs, r)
            end
        elseif type(refs) == 'table' then

        elseif tostring(refs) == 'name-of-signal-base' then
            table.insert(self.refs, refs)
        end

        setmetatable(opts, self)
        self.__index = self

        -- init plant refs
        opts:getRefs(refs)
        opts:getRefs(miscRefs, true)

        return opts
    end,





}

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
