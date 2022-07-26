-- send 20 cells / min in batches of 200 (one every 10 min) to avoid radiation outside of the nuclear plant (max. 200 at once or the drone completes the pickup while the port is still being loaded)

Port       = component.proxy('7A715EE34AE5A7134F4C1C93AC71EB0D')
Gate       = component.proxy('55ECCB4844111AD9D81E098D10026A57')
Panel      = component.proxy('EBC315A542D9F418CD86A6894F7EED2F')
Stacklight = component.proxy('CE65322A4D8DC29B7F631B9A10323476')
Buffer     = component.proxy('2EB1C4C6453C5D13AC00A4BF8E30AC65')
Display    = {
    ['batch']    = Panel:getModule(0, 7),
    ['buffer']   = Panel:getModule(3, 7),
    ['transfer'] = Panel:getModule(6, 7),
    ['port']     = Panel:getModule(9, 7),
    ['time']     = Panel:getModule(0, 4),
    ['status']   = Panel:getModule(3, 4),
    ['standby']  = Panel:getModule(5, 4)
}

Millis       = 0
BatchSize    = 200
BatchTime    = 10 * 60 * 1000                               -- in ms
Loading      = false
CanSend      = false
CurTime      = 10 * 1000                                    -- init delay
LoadItems    = 0
Port.standby = true                                         -- init port as paused

event.listen(Gate)

repeat

    local tDiff = computer.millis() - Millis

    Schedule:update(computer.millis())

    Millis = computer.millis()

    CurTime = CurTime - tDiff

    -- cap load delay to 5min max.
    if CurTime < -(BatchTime / 2) then
        CurTime = -BatchTime / 2
    end

    local signal, comp, port, item = event.pull(EVENT_DELAY)

    local portItems   = Port:getInventories()[1].itemCount
    local bufferItems = Buffer:getInventories()[1].itemCount

    if Loading then

        if Gate:canOutput(1) and Gate:getInput() and CanSend then
            Gate:transferItem(1)
            CanSend = false
        end

        if signal == 'ItemOutputted' then -- and (LoadItems + portItems) < BatchSize then
            LoadItems = LoadItems + 1
            CanSend   = true
        end

        if LoadItems >= BatchSize then
            Loading = false
            CurTime = CurTime + BatchTime
        end

    elseif Gate:canOutput(1) and portItems == 0 and bufferItems >= BatchSize and CurTime <= 0 then
        Loading = true
        CanSend = true
        Schedule:add(5, function() Port.standby = false end)-- open port 5 sec after opening storage
    end

    -- enable Port when loading items, so the drone can come and pick them up
    if not Loading and portItems == 0 and not Port.standby then
        LoadItems    = 0
        Port.standby = true
    end


    -- ----------
    -- display stuff below
    -- ----------

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
        Stacklight:getModule(0):setColor(0, 1, 0, 2)
        Stacklight:getModule(1):setColor(0.3, 0.3, 0, 0)
        Stacklight:getModule(2):setColor(0.3, 0, 0, 0)
    elseif CurTime > 0 then
        Display['status']:setColor(1, 0, 0, 0.5)
        Stacklight:getModule(0):setColor(0, 0.3, 0, 0)
        Stacklight:getModule(1):setColor(0.3, 0.3, 0, 0)
        Stacklight:getModule(2):setColor(1, 0, 0, 2)
    else
        if dspLoad > 0 then
            Display['status']:setColor(1, 0.8, 0, 1)
        else
            Display['status']:setColor(0, 0.1, 0, 0)
        end
        Stacklight:getModule(0):setColor(0, 0.3, 0, 0)
        Stacklight:getModule(1):setColor(1, 1, 0, 2)
        Stacklight:getModule(2):setColor(0.3, 0, 0, 0)
    end

until false