assert(type(Log) == 'table',               'Required Include "Log" not found')

function math.round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function math.hexfloat(hex)
    if #hex == 1 then
        hex = hex .. hex
    end
    return tonumber(hex, 16) / 255
end


-- ----------
-- ENUMS (mostly)
-- ----------

PORT = {                                                    -- Splitter + Merger
    LEFT   = 0,
    CENTER = 1,
    RIGHT  = 2
}

PLANT_STATE = {                                             -- 0 => 1 <=> 2 <=> 3 => 4 => 5
    STARTUP         = 1,                                    -- self startup
    CONNECT_WAIT    = 2,                                    -- self ready, waiting for connection
    PAUSED          = 3,                                    -- self ready, connected, waiting for go from extern
    WORKING         = 4,                                    -- working
    DISCONNECT_WAIT = 5,                                    -- self ready, managing disconnect
    SHUTDOWN        = 6                                     -- write temp vars to disk and restart
}

QTY = {
    FLUID_BUFFER_SMALL = 400,
    ITEM_STACK         = 200
}

--[[
    Color(<mixed>) : r, g, b, e
    usage:
    ..by predefined name
    Color($name [, emitStrength])
    e.g.: Color('fuel', 2) => 0.7, 0.4, 0.2, 2.0

    ..by Hex value
    Color($hexString [, emitStrength])
    e.g: Color('#F80') => 1.0, 0.5, 0.0, 1.0

    Color($hexwithEmitString)
    e.g: Color('#FFFFFF80') => 1.0, 1.0, 1.0, 0.5

    ..by rgb value
    Color($r, $g, $b [, $e])
    e.g: Color(255, 0, 255, 128) => 1.0, 0.0, 1.0, 0.5
  ]]
Color = setmetatable(
    {
        -- basic
        white    = {1.0, 1.0, 1.0},
        black    = {0.0, 0.0, 0.0},
        red      = {1.0, 0.0, 0.0},
        darkred  = {0.3, 0.0, 0.0},
        blue     = {0.0, 0.0, 1.0},
        darkblue = {0.0, 0.0, 0.5},
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
        water    = {0.1, 0.3, 0.5, 0.5}
    },
    {
        __call = function(this, ...)
            local args = {...}
            local col  = this[args[1]]
            local _, __, str = tostring(args[1]):find('^(%a+)%d$')
            if not col and str then
                col = this[str]
            end

            local hex, __, r, g, b, e = tostring(args[1]):find('^#(%x%x)(%x%x)(%x%x)(%x?%x?)$')
            if not hex then
                hex, __, r, g, b, e = tostring(args[1]):find('^#(%x)(%x)(%x)(%x?)$')
            end

            -- named
            if col then
                local emit = args[2] or col[4] or 1

                if emit < 0 then
                    emit = 0
                end

                if emit > 10 then
                    emit = 10
                end

                return col[1], col[2], col[3], emit

            -- hex
            elseif hex then
                local emit = nil
                if e == '' and args[2] then
                    emit = args[2]
                elseif e == '' then
                    emit = 1
                end

                return math.hexfloat(r), math.hexfloat(g), math.hexfloat(b), emit or math.hexfloat(e)

            -- rgb
            elseif #args == 3 or #args == 4 then
                args[4] = args[4] or 255
                return args[1] / 255, args[2] / 255, args[3] / 255, args[4] / 255
            else
                Log:write(Log.WARN, 'Color() - invalid params:', table.unpack(args))
                return 0, 0, 0, 1
            end
        end
    }
)

-- ----------
-- Funcs
-- ----------

function GetLevel(ref, stackSize, material)

    if type(ref) == 'table' then
        local pct, cur, max = 0, 0, 0
        for _, r in pairs(ref) do
            local p, c, m = GetLevel(r, stackSize, material)
            pct = pct + p
            cur = cur + c
            max = max + m
        end

        return pct, cur, max
    end

    if not ref or not ref.getInventories then
        return 0, 0, 0
    end

    local inv = ref:getInventories()[1]
    if inv ~= nil then                                      -- solid
        if material then
            local qty = 0
            for i = 0, inv.size - 1, 1 do
                local stack = inv:GetStack(i)
                if stack.item.type and stack.item.type.name == material then
                    stackSize = stack.item.type.max
                    qty = qty + stack.count
                end
            end
            return qty / (inv.size * (stackSize or 0)), qty, inv.size * (stackSize or 0)
        else
            return inv.ItemCount / (inv.size * stackSize), inv.ItemCount, inv.size * stackSize
        end
    elseif ref.fluidContent ~= nil then                     -- fluid
        return ref.fluidContent / ref.maxFluidContent, ref.fluidContent, ref.maxFluidContent
    end

    Log.write(Log.ERROR, 'getLevel() passed ref is no container!')
    return 0, 0, 0
end

function ScaleProdGroup(ref, on, off, state)
    local enabled = 0
    if off and ref.standby ~= state then
        ref.standby = state
    elseif on then
        if (ref.productivity > 0.2) then
            enabled = enabled + 1
        end
        if ref.standby == state then
            ref.standby = not state
        end
    end

    return enabled
end

function ScaleProduction(machines, curBuffer, maxBuffer, inverse)
    local step    = maxBuffer / #machines
    local state   = true
    local enabled = 0
    if inverse then
        state = false
    end

    -- todo: check for already paused machines and subtract from req. standby state

    for i, ref in pairs(machines) do
        local on  = curBuffer > (i + 1) * step
        local off = curBuffer <= i * step

        if type(ref) == 'table' then
            local en, max = {}, {}
            for j, r in pairs(ref) do
                en[j]  = ScaleProdGroup(r, on, off, state)
                max[j] = #ref
            end
            return en, max
        else
            enabled = ScaleProdGroup(ref, on, off, state)
            return enabled, #machines
        end
    end
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

function string.ucFirst(str)
    return str:gsub("^%l", string.upper)
end

function Keys(tbl)
    local set = {}
    for i, _ in pairs(tbl) do
        table.insert(set, i)
    end
    return table.unpack(set)
end

function BoolColor(cond)
    if cond then
        return 0, 1, 0, 1.0
    else
        return 1, 0, 0, 1.5
    end
end

