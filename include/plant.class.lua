assert(type(Log) == 'table', 'Required Include "Log" not found')

Plant = {
    name     = nil,
    state    = PLANT_STATE.STARTUP,
    eStopped = false,
    tmpFile  = '/tmp/' .. string.lower(DEVICE) .. '.var',

    stateFN = {'startup', 'connect', 'pause', 'working', 'disconnect', 'shutdown'},

    init = function(self, opts, refs, miscRefs)
        opts     = opts     or {}
        refs     = refs     or {}
        miscRefs = miscRefs or {}

        setmetatable(opts, self)
        self.__index = self

        -- init plant refs
        opts:getRefs(refs)
        opts:getRefs(miscRefs, true)

        return opts
    end,


    -- --------------------
    -- state updates
    -- --------------------

    update = function(self)
        if self.state < PLANT_STATE.STARTUP or self.state > PLANT_STATE.SHUTDOWN then
            Log:write(Log.ERROR, 'Plant:update() - invalid state:', self.state)
            return
        end

        if type(self[self.stateFN[self.state]]) == 'function' then
            self[self.stateFN[self.state]](self)
        end
    end,

    setState = function(self, newState)
        if newState < PLANT_STATE.STARTUP or newState > PLANT_STATE.SHUTDOWN then
            Log:write(Log.ERROR, 'Plant:setState() - invalid state received:', newState)
            return false
        end

        -- onLeave [on .. fn .. end]
        local n = 'on' .. self.stateFN[self.state]:ucFirst() .. 'End'
        if type(self[n]) == 'function' then
            self[n](self)
        end

        -- set [fn]
        self.state = newState

        -- onEnter [on .. fn]
        local n = 'on' .. self.stateFN[self.state]:ucFirst()
        if type(self[n]) == 'function' then
            self[n](self)
        end

        return true
    end,


    -- --------------------
    -- refs
    -- --------------------

    refs = {
        prod   = {},                                        -- nick + ' Machine'
        buffer = {},                                        -- nick + ' Buffer'
        misc   = {}                                         -- freeform
    },
    stats = {                                               -- {cur = 0, max = 0} same structure as "refs"
        prod   = {},
        buffer = {}
    },

    getRefs = function(self, nicks, isMisc)
        for k, n in pairs(nicks) do
            if isMisc then
                if type(n) == 'string' then
                    self.refs.misc[k] = component.proxy(component.findComponent(n))
                else
                    self.refs.misc[k] = n
                end
            else
                self.refs.prod[k]    = component.proxy(component.findComponent(n .. ' Machine'))
                self.refs.buffer[k]  = component.proxy(component.findComponent(n .. ' Buffer'))
                self.stats.prod[k]   = {cur = 0, max = 0}
                self.stats.buffer[k] = {cur = 0, max = 0}
            end
        end
    end,


    -- --------------------
    -- basic functionality
    -- --------------------

    stop = function(self, enable)
        if not enable and self.eStopped then
            return
        elseif (enable and self.state == PLANT_STATE.PAUSED) or (not enable and self.state == PLANT_STATE.WORKING) then
            return
        end

        for _, ref in pairs(self.refs.prod) do
            if type(ref) == 'table' then
                for _, r in pairs(ref) do
                    r.standby = enable
                end
            else
                ref.standby = enable
            end
        end
    end,


    -- --------------------
    -- save/load state to/from tmp file
    -- --------------------

    loadVars = function(self, ...)
        if not FS or not FS.open then
            Log:write(Log.ERROR, 'Plant:loadVars() - Filesystem global "FS" not set')
            return
        end

        if not self.tmpFile or not FS.isFile(self.tmpFile) then
            Log:write(Log.ERROR, 'Plant:loadVars() - Filename invalid or not pointing at file')
            return
        end

        local expectedVars = {...}

        local tmpFile = FS.open(self.tmpFile, 'r')

        local line, chr = '', ''
        repeat
            line = line .. chr
            chr = tmpFile:read(1)

            if chr == "\n" then
                local pos, len, name, val = line:find('(%w+) (.*)')
                if pos == 1 and name and val then
                    for i, ev in ipairs(expectedVars) do
                        if ev == name then
                            if val:sub(1, 1) == '[' and val:sub(#val) == ']' then -- table
                                self[name] = {}

                                if #val >= 5 then -- "[x y]" 5 chars minimum size for tbl with value
                                    val = val:sub(2, #val - 1) -- remove brackets
                                    repeat
                                        local _, n = val:find("\t")
                                        if n then
                                            local _, __, k, v = val:sub(1, n):find('(%w+) (.*)')
                                            val = val:sub(n + 1)
                                            self[name][k] = v
                                            print('x', k, v)
                                        end
                                    until not n

                                    local _, ___, k, v = val:find('(%w+) (.*)')
                                    print('y', k, v)
                                    self[name][k] = v
                                end
                            else -- non-table
                                self[name] = val
                            end
                            break
                        end
                    end
                else
                    Log:write(Log.ERROR, "Plant:loadVars() - malformated variable in tmp file: " .. line)
                end

                line = ''
                chr  = ''
            end
        until not chr

        tmpFile:close()
    end,

    saveVars = function (self, ...)
        if not FS or not FS.open then
            Log:write(Log.ERROR, 'Plant:loadVars() - Filesystem global [FS] not set')
        end

        if not self.tmpFile then
            return
        end

        local tmpFile = FS.open(self.tmpFile, 'w+')

        for _, var in ipairs({...}) do
            if type(self[var]) == 'table' then
                local tmp = ''
                for k, v in pairs(self[var]) do
                    if k and v then
                        tmp = tmp .. k .. ' ' .. tostring(v) .. "\t"
                    end
                end
                tmpFile:write(var .. ' [' .. tmp:sub(1, #tmp - 1) .. "]\n")
            else
                tmpFile:write(var .. ' ' .. tostring(self[var]) .. "\n")
            end
        end

        tmpFile:close()
    end
}
