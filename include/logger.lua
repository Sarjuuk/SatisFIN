Log = {
    NONE  = 0,
    ERROR = 1,
    WARN  = 2,
    INFO  = 3,
    DEBUG = 4,

    levels = {'ERROR', 'WARN', 'INFO', 'DEBUG'},


    write = function(self, level, ...)
        if (level <= LOGLEVEL) then
            print('['.. DEVICE .. '] [' .. Time(computer.time()) .. '] ' .. string.pad('[' .. self.levels[level] .. ']', 7, ' ') .. ' -', table.unpack({...}))
        end

        -- todo: create log file handler
    end
}