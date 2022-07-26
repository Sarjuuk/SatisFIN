Plant = {
    refs = {
        prod = {
            fuel     = 'Blender',
            packager = 'Packager'
        },
        buffer = {
            fuel = 'Buffer'
        },
        misc = {
            display = {'Panel Display',   0, 0},
            button  = {'Panel Indicator', 0, 0},
            gauge   = {'Panel Indicator', 1, 0}
        }
    },
    stats = {
        buffer = {
            fuel = {cur = 0, max = 300}
        }
    },
    getRefs = function(self, sub)
        sub = sub or self.refs

        for k, val in pairs(sub) do
            if type(val) == 'table' then
                sub[k] = self:getRefs(val)
            elseif string.find(val, 'Panel')  then
                local uuids = component.findComponent(val)
                return component.proxy(uuids[1]):getModule(sub[2], sub[3])
            else
                local uuids = component.findComponent(val)
                sub[k] = component.proxy(uuids)
            end
        end

        return sub
    end
}

function UpdateGauge(pct)
    local fg, bg, limit = 'red', 'white', BUFFER_MAX
    -- if not Plant.refs.prod.packager[1].standby then
    --     fg = 'white'
    --     bg = 'green'
    --     limit = BUFFER_MIN
    -- end

    Plant.refs.misc.gauge.percent = pct or 0

    Plant.refs.misc.gauge.limit = limit
    Plant.refs.misc.gauge:setBackgroundColor(Color(bg))
    Plant.refs.misc.gauge:setColor(Color(fg))
end


Plant:getRefs()

Plant.refs.misc.display.monospace = true
Plant.refs.misc.display.size = 48

UpdateGauge()

event:register(Plant.refs.misc.button, 'Trigger', function()
    Plant.refs.prod.packager[1].standby = not Plant.refs.prod.packager[1].standby
end)


Log:write(Log.INFO, 'System started')

BUFFER_MAX = 0.75
BUFFER_MIN = 0.50

repeat
    event:update()

    local pct, total, max = GetLevel(Plant.refs.buffer.fuel)

    -- machine output buffer
    local txt = ''
    local purge = 0
    for i, ref in ipairs(Plant.refs.prod.fuel) do
        local lvl = math.round(ref:getOutputInv().itemCount / 1000, 1)

        txt = txt .. string.pad(lvl, 5, ' ', true)

        if i == 3 then
            txt = txt .. "\n"
        end

        if lvl > 30 then
            purge = purge + 10
        elseif lvl > 5 then
            purge = purge + 1
        end
    end

    local factor = math.max(0, total - 200) / 100
    Plant.refs.misc.display.text = " Blender Buffer\n" .. txt

    if purge >= 10 or pct > 0.75 then
        Plant.refs.prod.packager[1].standby = false
    elseif purge == 0 and pct < 0.5 then
        Plant.refs.prod.packager[1].standby = true
    end

    UpdateGauge(pct)

    if Plant.refs.prod.packager[1].standby then
        Plant.refs.misc.button:setColor(Color('#3000'))
    else
        Plant.refs.misc.button:setColor(Color('green', 0.2))
    end
until false
