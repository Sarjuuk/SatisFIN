-- ----------
-- ENUMS (mostly)
-- ----------

PORT = {                                                    -- Splitter + Merger
    LEFT   = 0,
    CENTER = 1,
    RIGHT  = 2
}

PLANT_STATE = {
    STARTUP         = 0,
    CONNECT_WAIT    = 1,
    WORKING         = 2,
    DISCONNECT_WAIT = 3,
    SHUTDOWN        = 4
}

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

Color = setmetatable(
    {
        -- basic
        white    = {1.0, 1.0, 1.0},
        black    = {0.0, 0.0, 0.0},
        red      = {1.0, 0.0, 0.0},
        blue     = {0.0, 0.0, 1.0},
        green    = {0.0, 1.0, 0.0},
        yellow   = {1.0, 1.0, 0.0},
        purple   = {1.0, 0.0, 1.0},
        cyan     = {0.0, 1.0, 1.0},
        orange   = {1.0, 0.5, 0.0},
        -- material
        crudeOil = {0.1, 0.1, 0.1, 0.5},
        heavyOil = {0.5, 0.0, 0.6, 0.5},
        resin    = {0.0, 0.0, 0.5, 0.5},
        fuel     = {0.7, 0.4, 0.2, 0.5},
        plastic  = {0.3, 0.6, 0.9, 0.5},
        rubber   = {0.3, 0.3, 0.3, 0.5},
        hexfloat = function(hex)
            if #hex == 1 then
                hex = hex .. hex
            end
            return tonumber(hex, 16) / 255
        end
    },
    {
        __call = function(this, ...)
            local args = {...}
            local col  = this[args[1]]
            local hex, len, r, g, b, e = tostring(args[1]):find('^#(%x%x)(%x%x)(%x%x)(%x?%x?)$')
            if not hex then
                hex, len, r, g, b, e = tostring(args[1]):find('^#(%x)(%x)(%x)(%x?)$')
            end

            -- named
            if col then
                col[4] = args[4] or col[4] or 1

                if col[4] < 0 then
                    col[4] = 0
                end

                if col[4] > 10 then
                    col[4] = 10
                end

                return table.unpack(col)

            -- hex
            elseif hex then
                local emit = nil
                if e == '' and args[2] then
                    emit = args[2]
                elseif e == '' then
                    emit = 1
                end

                return this.hexfloat(r), this.hexfloat(g), this.hexfloat(b), emit or this.hexfloat(e)

            -- rgb
            elseif #args == 3 or #args == 4 then
                args[4] = args[4] or 255
                return args[1] / 255, args[2] / 255, args[3] / 255, args[4] / 255
            else
                print('Color() - invalid params:', table.unpack(args))
                return 0, 0, 0, 1
            end
        end
    }
)

print(Color('red', 0))
print(Color('green', 1))
print(Color(255, 128, 64))
print(Color(255, 0, 0, 128))
print(Color('#F0A'))
print(Color('#F0A3'))
print(Color('#FF00AA33'))
print(Color('#FF0088'))
-- assert(false)

-- ----------
-- Funcs
-- ----------

function math.round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function GetLevel(ref, stackSize, material)
    if not ref or not ref.getInventories then
        return 0, 0
    end

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

function ScaleProduction(machines, curBuffer, maxBuffer, inverse)
    local step    = maxBuffer / #machines
    local state   = true
    local enabled = 0
    if inverse then
        state = false
    end

    for i, ref in pairs(machines) do
        if curBuffer > (i + 1) * step and ref.standby ~= state then
            ref.standby = state
        elseif curBuffer <= i * step then
            if (ref.productivity > 0.2) then
                enabled = enabled + 1
            end
            if ref.standby == state then
                ref.standby = not state
            end
        end
    end

    return enabled, #machines
end


function NOP()
    -- zZZ
end

function CLS(gpu)
    if tostring(gpu) ~= 'GPU_T1_C' then
        Log:write(Log.ERROR, 'CLS() - Object passed is no GPU')
        return
    end
    gpu:setBackground(0, 0, 0, 1)
    gpu:setForeground(1, 1, 1, 1)
    local w, h = gpu:getSize()
    gpu:fill(0, 0, w, h, ' ')
    gpu:flush()
end

function Bind(fn, ...)
    local args = {...}

    return function(...)
        local newArg = {}
        for _, v in ipairs(args) do
            newArg[#newArg + 1] = v
        end
        for _, v in ipairs({...}) do
            newArg[#newArg + 1] = v
        end

        return fn(table.unpack(newArg))
    end
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

    while #tostring(str) < len do
        if front then
            str = sub .. str
        else
            str = str .. sub
        end
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

