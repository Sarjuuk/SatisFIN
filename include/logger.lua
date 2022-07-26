Log = {
    NONE  = 0,
    ERROR = 1,
    WARN  = 2,
    INFO  = 3,
    DEBUG = 4,

    levels = {'ERROR', 'WARN', 'INFO', 'DEBUG'},

    file = nil,

    start = function (self)
        if not self.file then
            self.file = FS.open('/logs/' .. DEVICE .. '.log', 'a+')
            if not self.file then
                print('['.. DEVICE .. '] [' .. Time(computer.time()) .. '] ' .. string.pad('[' .. self.levels.ERROR .. ']', 7, ' ') .. ' - Could not open log file for device!')
                return
            end

            self.file:write("\n    Log file started: " .. Time(computer.time()) .. "\n\n")
        end
    end,

    close = function(self)
        if self.file then
            self.file:write("\n    Log file closed: " .. Time(computer.time()) .. "\n")
            self.file:close()
        end
    end,

    write = function(self, level, ...)
        if (level > (LOG_LEVEL or 0)) then
            return
        end

        local str = '['.. DEVICE .. '] [' .. Time(computer.time()) .. '] ' .. string.pad('[' .. self.levels[level] .. ']', 7, ' ') .. ' ' .. self:stringify({...})

        print(str)

        if self.file then
            local _, err = pcall(function(out) Log.file:write(out) end, tostring(str) .. "\n")
            if err then
                print('Log:write(): ERROR -', err, str, "\n")
            end
        end
    end,

    stringify = function(self, obj, nested)
        local str = ''
        if type(obj) == 'table' then
            local parTbl = {}
            for n, q in pairs (obj) do
                if type(q) ~= 'string' then
                    q = self:stringify(q, true)
                end
                if nested then
                    table.insert(parTbl, n ..':' .. q)
                else
                    table.insert(parTbl, q)
                end
            end

            str = table.concat(parTbl, ' ')
            if nested then
                str = '[' .. str .. ']'
            end
        elseif type(obj) == 'function' then
            local dbg = debug.getinfo(obj, 'n')
            str = (dbg.name or 'fn').. '()'
        elseif obj == nil then
            str = 'nil'
        else
            str = tostring(obj)
        end

        return str
    end
}