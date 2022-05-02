event.delay = 0.10
event.components = {}

-- startup
event.clear()

function event.register(self, component, handler, forType)

    Log:write(Log.DEBUG, 'event:register() - ' .. tostring(component), table.unpack(handler), forType)

    event.listen(component)
    table.insert(self.components, {component, handler, forType or nil})
end

function event.update(self)
    local type, comp, data1, data2, data3, data4, data5, data6, data7 = event.pull(self.delay)

    if (type == nil) then
        return
    end

    Log:write(Log.DEBUG, 'event:update() - ' .. type, comp, data1, data2, data3, data4, data5, data6, data7)

    for i, entry in pairs(self.components) do
        if comp == entry[1] then
            if not entry[3] or entry[3] == type then
                if entry[2][2] ~= nil then
                    _G[entry[2][1]][entry[2][2]](_G[entry[2][1]], data1, data2, data3, data4, data5, data6, data7)
                else
                    entry[2][1](data1, data2, data3, data4, data5, data6, data7)
                end
            end
        end
    end
end

