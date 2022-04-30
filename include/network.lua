Net = {
    msg = {
        PING         = {'handlePingRecv'},
        PONG         = {'handlePongRecv'},
        HANDSHAKE    = {'handleHandshakeRcv'},
        ACK          = {nil},
        NAK          = {nil},
        REQ_M_STATE  = {nil},
        SND_M_STATE  = {nil},
        SET_M_VAR    = {nil},
        GET_M_VAR    = {nil},

    },
    card = nil,
    _self = nil,
    ports = {
        broadcast = 1000
    },

    inStack  = {},
    outStack = {},

    init = function(self, name)
        self.card = computer.getPCIDevices(findClass('NetworkCard'))[1]
        self.card:open(self.ports.broadcast)
        event:register(self.card, {'Net', 'receive'}, 'NetworkMessage')

        self._self = name

        --  init packet handler
        for n, tbl in pairs(self.msg) do
            if tbl[1] then
                tbl[1] = _G['Net'][tbl[1]]
            end
        end
    end,

    receive = function(self, srcUUID, msg, data2, data3)

        Log:write(Log.INFO, 'Net:receive() - ' .. srcUUID, msg, data2, data3)

        if self.msg[msg] then
            local handler, x, y, z = table.unpack(self.msg[msg])
            if not handler then
                Log:write(Log.INFO, 'Net:receive() - undefined handler for message: ' .. msg)
                return
            end

            self:logReceive(srcUUID, msg, data2, data3)

            handler(self, srcUUID, data2, data3)

        else
            Log:write(Log.INFO, 'Net:receive() - unknown msg type dicarded: ' .. msg)
        end
    end,


    send = function(self, targetUUID, targetPort, msg, data2, data3)

        Log:write(Log.INFO, 'Net:send() - ' .. tostring(targetUUID), targetPort, msg, data2, data3)

        self:logSend(targetUUID, msg, data2, data3)

        if targetUUID ~= nil then
            self.card:send(targetUUID, targetPort, msg, data2, data3)
        else
            self.card:broadcast(targetPort, msg, data2, data3)
        end
    end,

    handlePingRecv = function(self, srcUUID)

        Log:write(Log.INFO, 'Net:handlePingRecv() - ' .. srcUUID)

        self:send(srcUUID, self.ports.broadcast, 'PONG', self._self)
    end,

    handleHandshakeRcv = function(self, srcUUID, machine, port)

        Log:write(Log.INFO, 'Net:handleHandshakeRcv() - ' .. srcUUID, machine, port)

        local ok = true
        for m, p in pairs (self.ports) do
            if m == machine then
                Log:write(Log.INFO, 'Net:handleHandshakeRcv() - redefine already set connection with', m)
            elseif p == port then
                ok = false
                Log:write(Log.INFO, 'Net:handleHandshakeRcv() - cannot connect to' .. machine .. '. Port already in use by '.. m)
                break
            end
        end

        if ok then
            self:send(srcUUID, self.ports.broadcast, 'ACK', 'HANDSHAKE', port)
            self.ports[machine] = port
        else
            self:send(srcUUID, self.ports.broadcast, 'NAK', 'HANDSHAKE', port)
        end
    end,

    logSend = function(self, UUID, ...)
        if UUID ~= nil and self.outStack[UUID] == nil then
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
                table.insert(self.outStack[u], {...})
            end
        else
            table.insert(self.outStack[UUID], {...})
        end
    end,

    logReceive = function(self, UUID, ...)
        if self.inStack[UUID] == nil then
            self.inStack[UUID] = {}
        end

        table.insert(self.inStack[UUID], {...})
    end
}
