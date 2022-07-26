Net = {
    msg = {            -- handler, {expected data}
        -- Net
        PING             = {'handlePingRcv',       {}},
        PONG             = {'handlePongRcv',       {'string'}},
        CONNECT          = {'handleConnectRcv',    {'string', 'number'}},
        DISCONNECT       = {'handleDisconnectRcv', {}},
        ACK              = {nil,                   {'string'}},
        NAK              = {nil,                   {'string'}},
        REBOOT           = {'handleResetRcv',      {}},
        -- Plant Control
        REQ_PLANT_START  = {nil,                   {}},
        REQ_PLANT_STOP   = {nil,                   {}},
        REQ_ITEM         = {nil,                   {}},
        REQ_PLANT_STATUS = {nil,                   {}},
        RSP_PR_STATE     = {nil,                   {}},
        RSP_BU_STATE     = {nil,                   {}},
        REQ_PLANT_INFO   = {nil,                   {}},
        RSP_PLANT_INFO   = {nil,                   {'string', 'string' ,'string', 'number'}} -- name, title, color, orderIdx
    },
    nic     = nil,
    name    = nil,
    uuid    = '',
    ports   = { broadcast = 1000 },
    partner = {},

    rcvLED = nil,
    sndLED = nil,
    plc    = nil,

    inStack  = {},
    outStack = {},

    maxLog  = 50,

    init = function(self, name, rcv, snd)
        self.nic = computer.getPCIDevices(findClass('NetworkCard'))[1]
        assert(self.nic, 'Net:init() - no Network Interface Card found!')

        self.nic:open(self.ports.broadcast)
        event:register(self.nic, 'NetworkMessage', Bind(Net.receive, Net))

        self.name = name
        self.uuid = component.findComponent('PLC NIC')[1]

        if rcv and rcv.setColor then
            self.rcvLED = rcv
        end

        if snd and snd.setColor then
            self.sndLED = snd
        end

        --  init packet handler
        for n, tbl in pairs(self.msg) do
            if tbl[1] then
                if type(self[tbl[1]]) ~= 'function' then
                    Log:write(Log.DEBUG, 'Net:init() - no handler defined for ', tbl[1])
                else
                    tbl[1] = self[tbl[1]]
                end
            end
        end
    end,

    receive = function(self, srcUUID, port, msg, ...)
        local args = {...}

        Log:write(Log.DEBUG, 'Net:receive() -', srcUUID, msg, port, args)

        if srcUUID == self.uuid then                        -- no loopback allowed
            return
        end

        if self.rcvLED then
            self.rcvLED:setColor(Color('green', 0.5))
            Schedule:add(0.2, self.rcvLED.setColor, {self.rcvLED, Color('black')})
        end

        if self.msg[msg] then
            local handler, data = table.unpack(self.msg[msg])
            if not handler then
                Log:write(Log.ERROR, 'Net:receive() - discarded unhandled message type:',  msg)
                return
            end

            if #data ~= #args then
                Log:write(Log.ERROR, 'Net:receive() - discarded message with unexpected length: expected',  #data, 'got', #args, 'for', msg)
                return
            end

            local dataCheck = true
            for i, d in ipairs(data) do
                if type(d) ~= type(args[i]) then
                    Log:write(Log.ERROR, 'Net:receive() - data type mismatch: expected', type(args[i]), 'got', type(d))
                    dataCheck = false
                end
            end

            if not dataCheck then
                Log:write(Log.ERROR, 'Net:receive() - discarded message', msg, 'due to data type mismatch')
                return
            end

            self:logReceive(srcUUID, msg, table.unpack(args))

            handler(self, srcUUID, table.unpack(args))
        else
            Log:write(Log.WARN, 'Net:receive() - discarded unknown message type:', msg)
        end
    end,

    send = function(self, targetUUID, targetPort, msg, ...)
        local args = {...}

        Log:write(Log.DEBUG, 'Net:send() -', targetUUID or '<EVERYONE>', targetPort, msg, table.unpack(args))

        if self.sndLED then
            self.sndLED:setColor(Color('orange', 0.5))
            Schedule:add(0.2, self.sndLED.setColor, {self.sndLED, Color('black')})
        end

        self:logSend(targetUUID, msg, table.unpack(args))

        if targetUUID ~= nil then
            self.nic:send(targetUUID, targetPort, msg, table.unpack(args))
        else
            self.nic:broadcast(targetPort, msg, table.unpack(args))
        end
    end,

    handleResetRcv = function(self, srcUUID)

        Log:write(Log.INFO, 'Remote shutdown command received. Rebooting...')

        local delay = math.random(3)

        if not self.plc or not self.plc.shutdown then
            Schedule:add(delay + 1, computer.reset)
        else
            self.plc:shutdown(delay)
        end

        for n, uuid in pairs(self.partner) do
            if uuid == srcUUID then
                Schedule:add(delay, Net.send, {Net, srcUUID, self.ports[n], 'ACK', 'REBOOT'})
                break
            end
        end
    end,

    handlePingRcv = function(self, srcUUID)
        self:send(srcUUID, self.ports.broadcast, 'PONG', self.name)
    end,

    handlePongRecv = function(self, srcUUID, name)
        if self.partner[name] == srcUUID then
            Log:write(Log.WARN, 'Net:handlePongRecv() - net partner NIC changed - old:', self.partner[name], 'new:', srcUUID)
        end

        self.partner[name] = srcUUID
    end,

    handleConnectRcv = function(self, srcUUID, machine, port)
        local ok = true
        for m, p in pairs (self.ports) do
            if m == machine then
                Log:write(Log.INFO, 'Net:handleConnectRcv() - redefine already set connection with', m)
                self.nic:close(p)
            elseif p == port then
                ok = false
                Log:write(Log.WARN, 'Net:handleConnectRcv() - cannot connect to' .. machine .. '. Port already in use by '.. m)
                break
            end
        end

        if ok then
            self:send(srcUUID, self.ports.broadcast, 'ACK', 'CONNECT')
            self.nic:open(port)
            self.ports[machine] = port
        else
            self:send(srcUUID, self.ports.broadcast, 'NAK', 'CONNECT')
        end
    end,

    handleDisconnectRcv = function(self, srcUUID)
        local port, name
        for n, uuid in pairs(self.partner) do
            if uuid == srcUUID then
                port = self.ports[n]
                name = n
                break
            end
        end

        if port then
            self.ports[name] = nil
            self.partner[name] = nil
            self.nic:close(port)
            self:send(srcUUID, port, 'ACK', 'DISCONNECT')
        else
            self:send(srcUUID, port, 'NAK', 'DISCONNECT')
            Log:write(Log.WARN, 'Net:handleDisconnectRcv() - received disconnect command from unknown source:', srcUUID)
        end
    end,

    logSend = function(self, UUID, ...)
        if UUID and not self.outStack[UUID] then
            self.outStack[UUID] = {}
        end

        if UUID == nil then                                 -- write for already extablished conections
            local tmp = {}
            for u, _ in pairs(self.outStack) do
                tmp[u] = u
            end
            for u, _ in pairs(self.inStack) do
                tmp[u] = u
            end
            for u, _ in pairs(tmp) do
                if not self.outStack[u] then
                    self.outStack[u] = {}
                end
                table.insert(self.outStack[u], {...})
            end
        else
            table.insert(self.outStack[UUID], {...})
        end

        -- prune log
        for i, stack in pairs(self.outStack) do
            if #stack > self.maxLog then
                table.remove(self.outStack[i], 1)
            end
        end
    end,

    logReceive = function(self, UUID, ...)
        if self.inStack[UUID] == nil then
            self.inStack[UUID] = {}
        end

        table.insert(self.inStack[UUID], {...})

        -- prune log
        if #self.inStack[UUID] > self.maxLog then
            table.remove(self.inStack[UUID], 1)
        end
    end
}
