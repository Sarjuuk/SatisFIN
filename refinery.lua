-- -----------
-- vars
-- -----------

ExtFiles  = {
    '/include/utils.lua',
    '/include/network.lua',
    '/include/event.lua',
    '/include/scheduler.lua',
    '/include/logger.lua'
}

PlantName = 'refinery'

StackSize = 200                                             -- for resin
Rows      = 4
Cols      = 8
Stopped   = false

ResinBox = {}
ResinRef = {}
HorRef   = {}                                               -- heavy oil residue
EStops   = {}


-- ----------
-- create refs
-- ----------

ResinBox[10] = component.proxy('6FF8B3D1430A4A70ED9B97B00B6F43A8')
ResinBox[40] = component.proxy('2994885743DCD4D90A4A5DB6112DAA24')
ResinRef[10] = component.proxy('4B4BF0F545B4053C0B6AD697E39C6EF2')
ResinRef[40] = component.proxy('E09DF8744EA3D305D69B63AC7CAE9177')
ExcessTank   = component.proxy('74584ED84045C40E5A9C1E9B809796BE')
ExcessPump   = component.proxy('0342FA324668F2342A7B98AC8337C73B')
CokeRef      = {
    component.proxy('FB27FDD5417758EA8580BD940E34029F'),
    component.proxy('3B1E5284438742B7451CD990D61F8FDE')
}
EStopHolder  = {
    component.proxy('218A9CD547F83EA21F72519A221AAF3B'),
    component.proxy('080177FB4A5ED00585BCF8A358F63297')
}
HORBufer    = {
    component.proxy('33C38CB0415F0C199554AB897D871DD6'),
    component.proxy('75DD2F794CD44AE078D5E58885804157'),
    component.proxy('471DE73944C073361A1C8CACF798DC4E')
}
HORPump     = {
    component.proxy('31C2B0BC44A95741B515D0881AB5B24A'),
    component.proxy('796A58D244665F5F0370E28ACD974EE5'),
    component.proxy('49E1910D430F8AF967AFD2A4A82DDD39')
}

for i = 1, Rows, 1 do
    for j = 0, Cols, 1 do
        if j == 0 then
            HorRef[i] = {}
        end

    local x = component.findComponent('hor_' .. i .. '_' .. j)[1]
    if x ~= nil then
        HorRef[i][j] = component.proxy(x)
    end
  end
end


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

function HandleExcessOil()
    local level = GetLevel(ExcessTank)
    if     level > 0.3 and     CokeRef[1].standby then
        CokeRef[1].standby = false
    elseif level < 0.1 and not CokeRef[1].standby then
        CokeRef[1].standby = true
    elseif level > 0.7 and     CokeRef[2].standby then
        CokeRef[2].standby = false
    elseif level < 0.5 and not CokeRef[2].standby then
        CokeRef[2].standby = true
    end

    if level > 0.1 then
        ExcessPump.standby = false
    else
        ExcessPump.standby = true
    end
end

function HandleExcessResin()
    -- inv:getStack(slotIdx)

    for i, ref in pairs(ResinBox) do
        local level = GetLevel(ref, StackSize)

        if level > 0.5 and not ResinRef[i].standby then
             ResinRef[i].standby = true
         elseif level < 0.2 and ResinRef[i].standby then
            ResinRef[i].standby = false
        end

        Log:write(Log.INFO, 'ResinBox ' .. i .. ': ' .. math.round(level * 100, 2) .. '% - Prod. Enabled: ' .. tostring(not ResinRef[i].standby))
    end
end

function HandleEStop()
    -- toggle state
    Stopped = not Stopped

    -- update buttons
    for i, ref in pairs(EStops) do
        if Stopped then
            ref:setColor(1, 0, 0, 0.8)
        else
            ref:setColor(1, 0, 0, 0)
        end
    end

    --  update machines
    for i, tbl in pairs(HorRef) do
        for j, ref in pairs(tbl) do
            ref.standby = Stopped
        end
    end

    for i, ref in pairs(ResinRef) do
        ref.standby = Stopped
    end

    for i, ref in pairs(CokeRef) do
        ref.standby = Stopped
    end

    ExcessPump.standby = Stopped
end


Log:write(Log.INFO, 'System started')


-- ----------
-- init
-- ----------

Net:init(PlantName)

for i, ref in pairs(EStopHolder) do
    local mod = ref:getModule(0, 0)
    event:register(mod, {HandleEStop}, 'Trigger')
    EStops[i] = mod
end


-- ----------
-- run
-- ----------

repeat
    event:update()

    Schedule:update(computer.millis())

    if Stopped then
        goto continue
    end

    -- burn excess hor
    HandleExcessOil()

    -- throttle resin refineries on demand
    HandleExcessResin()

    ::continue::                                            -- fucking hell!

until false
