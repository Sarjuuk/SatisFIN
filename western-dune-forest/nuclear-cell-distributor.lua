-- send 20 cells / min in batches of 200 (one every 10 min) to avoid radiation outside of the nuclear plant (max. 200 at once or the drone completes the pickup while the port is still being loaded)

Port       = component.proxy('7A715EE34AE5A7134F4C1C93AC71EB0D')
Gate       = component.proxy('2B239B0E4F868D494877B79EA969FEB7')
Panel      = component.proxy('F0D0EE0E4FF77A350A7A45B4DC4C05D4')
Stacklight = component.proxy('15B7F7E346F8D4F9954C258A33290617')    -- old Indicator
Buffer     = component.proxy('8E9881344C320D8E15EEAE8B0E730B59')
Display    = {
    batch    = Panel:getModule(0, 7),
    buffer   = Panel:getModule(3, 7),
    transfer = Panel:getModule(6, 7),
    port     = Panel:getModule(9, 7),
    time     = Panel:getModule(0, 4),
    status   = Panel:getModule(3, 4),
    standby  = Panel:getModule(5, 4),
    reset    = Panel:getModule(9, 1),
    waste    = Panel:getModule(0, 0),
}

BatchSize    = 200
BatchTime    = 10 * 60 * 1000                               -- in ms
InitTime     = 10 * 1000                                    -- check if we start game with cells already in port or en route
CurTime      = BatchTime * (1 - math.min(1, (Buffer:getInventories()[1].itemCount / BatchSize)))
Millis       = 0
Loading      = false
CanSend      = false
LoadItems    = 0
Port.standby = false                                        -- init port as working
-- approximate time to next pickup from initial inventory (min: 10s)
Display.reset:setColor(1, 0, 0, 0)
Display.waste.monospace = true
Display.waste.size = 46 -- 16 chars wide

event.listen(Gate)
event.listen(Display.reset)

repeat

    local tDiff   = computer.millis() - Millis
    local initOld = InitTime

    Schedule:update(computer.millis())

    Millis = computer.millis()

    CurTime  = CurTime - tDiff
    InitTime = math.max(0, InitTime - tDiff)

    local signal, comp = event.pull(EVENT_DELAY)

    local portItems   = Port:getInventories()[1].itemCount
    local bufferItems = Buffer:getInventories()[1].itemCount

    -- after init time no items in port? -> disable port so regular routine can work
    if initOld > 0 and InitTime == 0 and portItems == 0 then
        Port.standby = true
    end

    if Loading then

        if Gate:canOutput(PORT.CENTER) and Gate:getInput() and CanSend then
            Gate:transferItem(PORT.CENTER)
            CanSend = false
        end

        if signal == 'ItemOutputted' and comp == Gate then -- and (LoadItems + portItems) < BatchSize then
            LoadItems = LoadItems + 1
            CanSend   = true
        end

        if LoadItems >= BatchSize then
            Loading = false
            CurTime = CurTime + BatchTime
        end

    elseif Gate:canOutput(PORT.CENTER) and portItems == 0 and bufferItems >= BatchSize and CurTime <= 0 then
        Loading = true
        CanSend = true
        Schedule:add(3, function() Port.standby = false end)-- open port 3 sec after opening storage
    end

    -- enable Port when loading items, so the drone can come and pick them up
    if not Loading and portItems == 0 and not Port.standby then
        LoadItems    = 0
        Port.standby = true
    end


    -- --------------------
    -- handle reset request
    -- --------------------

    if signal == 'Trigger' and comp == Display.reset then
        Display.reset:setColor(1, 0, 0, 2)
        Schedule:add(0.2, Display.reset.setColor, {Display.reset, 1, 0, 0, 0})
        Schedule:add(0.4, Display.reset.setColor, {Display.reset, 1, 0, 0, 1})
        Schedule:add(0.6, Display.reset.setColor, {Display.reset, 1, 0, 0, 0})
        Schedule:add(0.8, Display.reset.setColor, {Display.reset, 1, 0, 0, 1})
        Schedule:add(1.0, Display.reset.setColor, {Display.reset, 1, 0, 0, 0})
        Schedule:add(1.2, computer.reset)
    end


    -- --------------------
    -- calc waste space
    -- --------------------

    local endStorage = component.proxy(component.findComponent('Container'))
    local pct, cur, max = GetLevel(endStorage, 500)
    local wasteDsp = string.pad(cur, 6, ' ', true) .. ' / ' .. max .. "\n".. string.pad(math.round(pct, 2) .. '%', 15, ' ', true) .. "\n"
    wasteDsp = wasteDsp .. '▌'
    for i=1, 14, 1 do
        if (i / 14) < (pct / 100) then
            wasteDsp = wasteDsp .. '█'
        else
            wasteDsp = wasteDsp .. ' '
        end
    end
    wasteDsp = wasteDsp .. '▐'


    Display.waste.text = wasteDsp


    -- --------------------
    -- display stuff below
    -- --------------------

    local dspLoad = math.max(0, LoadItems - portItems)
    local dspTime = math.floor(CurTime / (60 * 1000)) .. ':' .. string.format('%02d', math.floor(math.fmod(CurTime, 60 * 1000) / 1000))
    if CurTime < 0 then
        dspTime = '0:00'
    end

    if not Port:getPowerConnectors()[1]:getPower().hasPower then
        Display['standby']:setColor(1, 0, 0, 1)
    elseif Port.standby then
        Display['standby']:setColor(1, 1, 0, 0.5)
    else
        Display['standby']:setColor(0, 1, 0, 1)
    end

    Display['batch']:setText(BatchSize)
    Display['transfer']:setText(dspLoad)
    Display['port']:setText(portItems)

    Display['buffer']:setText(bufferItems)
    Display['buffer']:setColor(BoolColor(BatchSize < bufferItems))

    Display['time']:setText(dspTime)
    Display['time']:setColor(BoolColor(CurTime <= 0))

    if Loading then
        Display['status']:setColor(0, 1, 0, 0.5)
        Stacklight:setColor(0, 1, 0, 2)
    elseif CurTime > 0 then
        Display['status']:setColor(1, 0, 0, 0.5)
        Stacklight:setColor(1, 0, 0, 2)
    else
        if dspLoad > 0 then
            Display['status']:setColor(1, 0.8, 0, 1)
        else
            Display['status']:setColor(0, 0.1, 0, 0)
        end
        Stacklight:setColor(1, 1, 0, 2)
    end

until false