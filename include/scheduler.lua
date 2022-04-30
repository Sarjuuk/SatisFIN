Schedule = {
    events     = {},            -- [time, func, params, reschedule]
    lastUpdate = 0,

    update = function(self, microTime)

        -- Log:write(Log.DEBUG, 'Schedule::update()', Time(microTime / 1000))

        for i, event in pairs(self.events) do
            if event[1] <= microTime then
                event[2](table.unpack(event[3]))
                if event[4] <= 0 then
                    table.remove(self.events, i)
                else
                    while self.events[i][1] < microTime do
                        self.events[i][1] = self.events[i][1] + (self.events[i][4] * 1000)
                    end
                end
            end
        end

        self.lastUpdate = microTime
    end,

    add = function(self, timeDelta, func, params, repeatTimeDelta)
        local newIdx = math.max(0, Keys(self.events)) + 1

        Log:write(Log.DEBUG, 'Schedule:add() - new event #' .. newIdx ..':', timeDelta, func, params, repeatTimeDelta)

        self.events[newIdx] = {
            self.lastUpdate + (timeDelta * 1000),
            func,
            params or {},
            repeatTimeDelta or 0
        }

        return newIdx
    end,

    remove = function(self, idx)
        table.remove(self.events, idx)
    end

}