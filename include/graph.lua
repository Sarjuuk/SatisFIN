assert(type(Log) == 'table', 'Required Include "Log" not found')

Graph = {
    gpu    = nil,

    height     = 0,
    barWidth   = 9,
    groupWidth = 3,
    fullLen    = 0,

    names = {
        crudeOil = 'Cr. Oil',
        heavyOil = 'He. Oil',
        resin    = 'P.Resin',
        fuel     = 'Fuel',
        plastic  = 'Plastic',
        rubber   = 'Rubber'
    },

    new = function (self, o)
        o = o or {}                                         -- create object if user does not provide one

        if type(o.data) ~= 'table' then
            o.data = {}
            o.lastData = {}
        end

        if type(o.info) ~= 'table' then
            o.info = {}
        end

        setmetatable(o, self)
        self.__index = self
        return o
    end,

    init = function(self, gpu, height, posX, posY)
        if tostring(gpu) ~= 'GPU_T1_C' then
            Log:write(Log.ERROR, 'Graph:init() - No GPU T1 found!')
            return
        end
        self.gpu = gpu

        if height < 20 then
            height = 20
            Log:write(Log.WARN, 'Graph:init() - min. Graph size forced to 20')
        end

        if posX < 0 then
            posX = 0
        end

        if posY < 0 then
            posY = 0
        end

        self.offX = posX
        self.offY = posY

        self.height  = height
        self.fullLen = math.floor((self.height - 2) * 0.8)

        self:cls()
    end,

    cls = function(self)
        self.gpu:setBackground(Color('black'))
        self.gpu:setForeground((Color('white')))
        local w, _ = self.gpu:getSize()
        self.gpu:fill(self.offX, self.offY, w, self.height + 3, ' ') -- +3 for temp. extra text below
    end,

    addData = function(self, group, type, name, cur, max)
        -- type:1=prod, 2=buffer
        if not self.data[group] or not self.data[group][name] then
            self.data[group] = self.data[group] or {}
            self.data[group][name]     = {{0, 0}, {0, 0}}
            self.lastData[group][name] = {{0, 0}, {0, 0}}
        end

        self.lastData[group][name][type] = self.data[group][name][type]
        self.data[group][name][type] = {cur, max}
    end,

    addInfo = function(self, group, type, name, title, color, order)
        -- type:1=plant, 2=prodLine
        if not self.info[group] or not self.info[group][name] then
            self.info[group] = self.info[group] or {}
            self.info[group][name] = {{}, {}}
        end

        self.info[group][name][type] = {title, color, order}
    end,

    drawSystem = function(self)
        -- get dims
        local totalWidth  = 5 + 1 + 1                               -- 100% text:5,  vert Bar: 1, arrow: 1

        for i, grp in pairs(self.data) do
            for j, tbl in pairs(self.data[i]) do
                totalWidth = totalWidth + self.barWidth
            end
            totalWidth = totalWidth + self.groupWidth
        end

        -- set colors
        self.gpu:setForeground(1, 1, 1, 1)
        self.gpu:setBackground(0, 0, 0, 1)

        -- vert. bar
        self.gpu:setText(5 + self.offX, 0 + self.offY, '▲')
        self.gpu:fill(5 + self.offX, 1 + self.offY, 1, self.height - 3, '│')

        -- 100%
        self.gpu:setText(0 + self.offX, self.offY + self.height - self.fullLen - 2 , '100% ┼')
        self.gpu:fill(6 + self.offX, self.offY + self.height - self.fullLen - 2, totalWidth - 7, 1, '─')

        -- corner
        self.gpu:setText(5 + self.offX, self.height - 2 + self.offY, '└')

        -- draw hor. bar
        self.gpu:setText(totalWidth - 1 + self.offX, self.height - 2 + self.offY, '►')
        self.gpu:fill(6 + self.offX, self.height - 2 + self.offY, totalWidth - 7, 1, '─')
    end,

    drawBar = function(self, offX, title, material, prodBar, bufferBar)
        if prodBar[2] <= 0 then
            return 0
        end
        material = material or 'white'

        self.gpu:setForeground(Color(material, 0.5))
        self.gpu:setBackground(Color('black'))

        -- base
        self.gpu:setText(offX + 1, self.height - 2 + self.offY, '▀▀▀▀▀▀▀')

        -- bars
        local barLen  = math.min(self.height - 2, (prodBar[1] / prodBar[2]) * self.fullLen - 1)
        local addHalf = math.fmod(barLen, 1) > 0.5 or prodBar[1] == prodBar[2]
        for i = 1, math.floor(barLen), 1 do
            if i == self.fullLen then
                self.gpu:setForeground(Color('black'))
                self.gpu:setBackground(Color(title, 0.5))
                self.gpu:setText(offX + 1, self.offY + self.height - (i + 2), '───────')
                self.gpu:setBackground(Color('black'))
                self.gpu:setForeground(Color(title, 0.5))
            else
                self.gpu:setText(offX, self.offY + self.height - (i + 2), ' ████    ')
            end
        end

        if addHalf then
            self.gpu:setText(offX + 1, self.offY + self.height - math.floor(barLen + 3), '▄▄▄▄')
        end

        self.gpu:setForeground(Color(material, 1))
        self.gpu:setBackground(Color('black'))

        -- draw buffer bar over prod bar
        if bufferBar[2] > 0 then
            local barLen  = math.min(self.height - 2, (bufferBar[1] / bufferBar[2]) * self.fullLen - 1)

            for i = 1, math.floor(barLen), 1 do
                if i == self.fullLen then
                    self.gpu:setForeground(Color('black'))
                    self.gpu:setBackground(Color(material, 1))
                    self.gpu:setText(offX + 5, self.offY + self.height - (i + 2), '───')
                    self.gpu:setBackground(Color('black'))
                    self.gpu:setForeground(Color(material, 1))
                else
                    self.gpu:setText(offX + 5, self.offY + self.height - (i + 2), '▐██')
                end
            end
        end

        self.gpu:setForeground(Color('white'))

        -- text
        self.gpu:setText(1 + offX, self.height - 1 + self.offY, self.names[title] or title)

        self.gpu:setText(1 + offX, self.height + 0 + self.offY, math.round(prodBar[1] / prodBar[2] * 100, 2) .. '%')
        self.gpu:setText(1 + offX, self.height + 1 + self.offY, prodBar[1] .. ' / ' .. prodBar[2])
        if bufferBar[2] > 0 then
            self.gpu:setText(1 + offX, self.height + 2 + self.offY, math.ceil(bufferBar[1]))
        end

        return self.barWidth
    end,

    drawGroup = function(self, offX, group, last)
        local barIdx  = 0

        offX = offX + 1
        for name, bars in pairs(group) do
            local material = nil                            -- todo: get for real
            offX = offX + self:drawBar(offX, name, material, bars[1], bars[2])
            barIdx = barIdx + 1
        end

        offX = offX + 1

        -- vert. divider
        if not last then
            self.gpu:setText(offX, self.height - 2 + self.offY, '┼')
            self.gpu:setForeground(1, 1, 1, 0.5)
            self.gpu:fill(offX, 1 + self.offY, 1, self.height - 3, '│')
            self.gpu:setText(offX, self.offY + self.height - self.fullLen - 2 , '┼')
            self.gpu:setForeground(1, 1, 1, 1)
            offX = offX + 1
        end

        return offX
    end,

    draw = function(self)
        self:cls()
        self:drawSystem()

        local lastGrp = nil
        local totalOffX = 6 + self.offX

        for i, grp in pairs(self.data) do
            if lastGrp then
                totalOffX = self:drawGroup(totalOffX, lastGrp, false)
            end
            lastGrp = grp
        end
        if lastGrp then
            self:drawGroup(totalOffX, lastGrp, true)
        end

        self.gpu:flush()
    end
}
