event.delay = 0.10
event.components = {}

function event:register(component, forType, handler)

    Log:write(Log.DEBUG, 'event:register() - ' .. tostring(component), handler, forType)

    event.listen(component)
    table.insert(self.components, {component, handler, forType or nil})
end

function event:detach(component, forType)

    Log:write(Log.DEBUG, 'event:detach() - ' .. tostring(component), forType)

    local canIgnore = true
    for i, tbl in ipairs(self.components) do
        if tbl[1].hash == component.hash then
            if forType and tbl[3] == forType then
                self.components[i] = nil
            elseif forType then
                canIgnore = false
            end
        end
    end

    if canIgnore then
        event.ignore(component)
    end
end

function event:update()
    local type, comp, data1, data2, data3, data4, data5, data6, data7 = event.pull(self.delay)

    if (type == nil) then
        return
    end

    Log:write(Log.DEBUG, 'event:update() - ' .. type, comp, data1, data2, data3, data4, data5, data6, data7)

    for i, entry in pairs(self.components) do
        if comp == entry[1] then
            if not entry[3] or entry[3] == type then
                entry[2](data1, data2, data3, data4, data5, data6, data7)
                return
            end
        end
    end

    Log:write(Log.WARN, 'event:update() - unhandled event ' .. type, comp, data1, data2, data3, data4, data5, data6, data7)
end

-- startup
event.clear()
