ExtFiles  = {
    '/include/utils.lua',
    '/include/network.lua',
    '/include/event.lua',
    '/include/scheduler.lua',
    '/include/logger.lua'
}

PlantName = 'preprocessing'

 -- ----------
 -- load helper funcs
 -- ----------

 if (not fs or not fs.isFile) then
    computer.panic('Expected Filesystem ref not set up!')
 else
     for i, file in pairs(ExtFiles) do
        if not fs.isFile(file) then
            computer.panic(file .. ' not found!')
        else
            fs.doFile(file)
        end
    end
end

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

    c = {
        r=red   * blItr / 255,
        g=green * blItr / 255,
        b=blue  * blItr / 255
    }

    for _, light in pairs(lights) do
        lightData = light:getPrefabSignData()
        lightData.background = c
        light:setPrefabSignData(lightData)
    end

end

Log:write(Log.INFO, 'System started')


-- ----------
-- init
-- ----------

blItr = 100
blDir = true

local mPlastic = {}
local mRubber  = {}
local lights   = {component.proxy('ECB1E4744DA6DC0EFA7BD281F7E1163C', '48F1F46940E59119E61153BDBE992F25')}

ru, pl   = component.findComponent('Rubber', 'Plastic')
mRubber  = component.proxy(ru)
mPlastic = component.proxy(pl)

Net:init(PlantName)


-- ----------
-- run
-- ----------

repeat
    event:update()

    Schedule:update(computer.millis())

    statusR = 0
    statusP = 0

    for i in pairs(mPlastic) do
        if mPlastic[i].productivity > 0.9 then
            statusP = statusP | (1 << (i - 1))
        end
    end

    for i in pairs(mRubber) do
        if mRubber[i].productivity > 0.9 then
            statusR = statusR | (1 << (i - 1))
        end
    end

    blink(lights, 5, 0, 1, 0)

until false

