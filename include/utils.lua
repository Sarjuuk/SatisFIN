function math.round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    local result = math.floor(num * mult + 0.5) / mult

    if num >= 10 and #tostring(result) == 4 then
        result = result .. 0
    elseif num < 10 and #tostring(result) == 3 then
        result = result .. 0
    end
    return result
end

function GetLevel(ref, stackSize, material)
    local inv = ref:getInventories()[1]
    if inv ~= nil then                   -- solid
        if material then
            local qty = 0
            for i = 0, inv.size - 1, 1 do
                local stack = inv:GetStack(i)
                if stack.item.type and stack.item.type.name == material then
                    stackSize = stack.item.type.max
                    qty = qty + stack.count
                end
            end
            return qty / (inv.size * (stackSize or 0)), qty
        else
            return inv.ItemCount / (inv.size * stackSize), inv.ItemCount
        end
    elseif ref.fluidContent ~= nil then  -- fluid
        return ref.fluidContent / ref.maxFluidContent, ref.fluidContent
    else
        Log.write(Log.ERROR, 'getLevel() passed ref is no container!')
        computer.beep(1)
    end

    return 0, 0
end

function NOP()
    -- zZZ
end

function Time(time)
 -- local d = math.floor(time/86400)
    local remaining = time % 86400
    local h = math.floor(remaining/3600)
    remaining = remaining % 3600
    local m = math.floor(remaining/60)
    remaining = remaining % 60
    local s = remaining
    if (h < 10) then
      h = "0" .. tostring(h)
    end
    if (m < 10) then
      m = "0" .. tostring(m)
    end
    if (s < 10) then
      s = "0" .. tostring(s)
    end
    return  h..':'..m..':'..s
end

function string.pad(str, len, sub, front)

    sub   = sub or ' '
    front = front or false

    while #str < len do
        if front then
            str = sub .. str
        end
        str = str .. sub
    end
    return str
end

function Keys(tbl)
    local set = {}
    for i, _ in pairs(tbl) do
        table.insert(set, i)
    end
    return table.unpack(set)
end


Log = {
    NONE  = 0,
    ERROR = 1,
    WARN  = 2,
    INFO  = 3,
    DEBUG = 4,

    levels = {'ERROR', 'WARN', 'INFO', 'DEBUG'},


    write = function(self, level, ...)
        if (level <= LOGLEVEL) then
            print('['.. DEVICE .. '] [' .. Time(computer.time()) .. '] ' .. string.pad('[' .. self.levels[level] .. ']', 7, ' ') .. ' -', table.unpack({...}))
        end

        -- todo: create log file handler
    end
}
