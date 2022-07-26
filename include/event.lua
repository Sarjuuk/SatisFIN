--[[
    usage:
    Merger  = component.proxy(<mergerUUID>)
    event:register(Merger , 'ItemOutputted', print) -- just dump info to console
    event:register(Merger , 'ItemRequest', function (port, item)
        Merger:transferItem(port)
    end)

    -- in the main program loop
    repeat
        -- add this
        event:update()
    until false
  ]]

event.components = {}

function event:register(component, forType, handler)

    Log:write(Log.DEBUG, 'event:register() -', tostring(component), handler, forType)

    event.listen(component)
    table.insert(self.components, {component, handler, forType or nil})
end

function event:detach(component, forType)

    Log:write(Log.DEBUG, 'event:detach() -', tostring(component), forType)

    local canIgnore = true
    for i, tbl in ipairs(self.components) do
        if tbl[1].hash == component.hash then
            if not forType then
                self.components[i] = nil
                break
            elseif tbl[3] == forType then
                self.components[i] = nil
            else
                canIgnore = false
            end
        end
    end

    if canIgnore then
        event.ignore(component)
    end
end

function event:update(delay)
    local data = {event.pull(delay or EVENT_DELAY or 0.05)}

    if #data == 0 then
        return
    end

    Log:write(Log.DEBUG, 'event:update() -', table.unpack(data))

    local type = table.remove(data, 1)
    local comp = table.remove(data, 1)

    local handled = false
    for i, entry in ipairs(self.components) do
        if comp == entry[1] then
            if not entry[3] or entry[3] == type then
                entry[2](table.unpack(data))
                handled = true
            end
        end
    end

    if not handled then
        Log:write(Log.WARN, 'event:update() - unhandled event', type, comp, table.unpack(data))
    end
end

-- startup
event.clear()
