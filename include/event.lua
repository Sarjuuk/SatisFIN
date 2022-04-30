event.delay = 0.10
event.components = {}

-- startup
event.clear()

function event.register(self, component, handler, forType)

    Log:write(Log.INFO, 'event:register() - ' .. tostring(component), table.unpack(handler), forType)

    event.listen(component)
    table.insert(self.components, {component, handler, forType or nil})
end

function event.update(self)
    local type, comp, srcUUID, inPort, data1, data2, data3 = event.pull(self.delay)

    if (type == nil) then
        return
    end

    Log:write(Log.INFO, 'event:update() - ' .. type, comp, srcUUID, inPort, data1, data2, data3)

    for i, entry in pairs(self.components) do
        if comp == entry[1] then
            if not entry[3] or entry[3] == type then
                if entry[2][2] ~= nil then
                    _G[entry[2][1]][entry[2][2]](_G[entry[2][1]], srcUUID, data1, data2, data3)
                else
                    entry[2][1](srcUUID, data1, data2, data3)
                end
            end
        end
    end
end

