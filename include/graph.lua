Graph = {
    gpu    = nil,

    height     = 0,
    barWidth   = 9,
    groupWidth = 3,
    fullLen    = 0,

    colors = { -- r g b a
        crudeOil = {0.1, 0.1, 0.2, 0.5},
        heavyOil = {0.5, 0.0, 1.0, 0.5},
        resin    = {0.0, 0.4, 1.0, 0.5},
        fuel     = {1.0, 0.5, 0.0, 0.5},
        plastic  = {0.0, 0.7, 1.0, 0.5},
        rubber   = {0.4, 0.4, 0.4, 0.5},
        white    = {1.0, 1.0, 1.0, 1.0},
        black    = {0.0, 0.0, 0.0, 1.0}
    },

    names = {
        crudeOil = 'Cr. Oil',
        heavyOil = 'He. Oil',
        resin    = 'P.Resin',
        fuel     = 'Fuel',
        plastic  = 'Plastic',
        rubber   = 'Rubber'
    },

    data     = {},
    lastData = {},

    init = function(self, gpu, height)
        if tostring(gpu) ~= 'GPU_T1_C' then
            Log:write(Log.ERROR, 'Graph:init() - No GPU T1 found!')
            return
        end
        self.gpu = gpu

        if height < 20 then
            height = 20
            Log:write(Log.WARN, 'Graph:init() - min. Graph size forced to 20')
        end

        self.height  = height
        self.fullLen = math.floor((self.height - 3) * 0.8)

        self:cls()
    end,

    cls = function(self)
        self.gpu:setBackground(table.unpack(self.colors.black))
        self.gpu:setForeground(table.unpack(self.colors.white))
        local w, h = self.gpu:getSize()
        self.gpu:fill(0, 0, w, h, ' ')
    end,

    addData = function(self, group, name, type, cur, max)
        -- type:1=prod, 2=buffer
        if self.data[group] == nil then
            self.data[group]     = {}
            self.lastData[group] = {}
        end

        if self.data[group][name] == nil then
            self.data[group][name]     = {{0, 0}, {0, 0}}
            self.lastData[group][name] = {{0, 0}, {0, 0}}
        end

        self.lastData[group][name][type] = self.data[group][name][type]
        self.data[group][name][type] = {cur, max}
    end,

    drawSystem = function(self)
        -- get dims
        local totalHeight = self.height
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
        self.gpu:fill(5 + self.offX, 1 + self.offY, 1, totalHeight - 3, '│')

        -- 100%
        self.gpu:setText(0 + self.offX, self.offY + self.height - self.fullLen - 2 , '100% ┼')
        self.gpu:fill(6 + self.offX, self.offY + self.height - self.fullLen - 2, totalWidth - 7, 1, '─')

        -- corner
        self.gpu:setText(5 + self.offX, totalHeight - 2 + self.offY, '└')

        -- draw hor. bar
        self.gpu:setText(totalWidth - 1 + self.offX, totalHeight - 2 + self.offY, '►')
        self.gpu:fill(6 + self.offX, totalHeight - 2 + self.offY, totalWidth - 7, 1, '─')
    end,

    drawBar = function(self, offX, title, prodBar, bufferBar)
        if prodBar[2] <= 0 then
            return 0
        end

        local fgCol = self.colors[title] or self.colors.white
        local bgCol = self.colors.black

        self.gpu:setForeground(table.unpack(fgCol))
        self.gpu:setBackground(table.unpack(bgCol))

        -- descriptor
        self.gpu:setText(1 + offX, self.height - 1 + self.offY, self.names[title] or title)

        -- base
        self.gpu:setText(offX + 1, self.height - 2 + self.offY, '▀▀▀▀▀▀▀')

        -- bars
        local barLen  = (prodBar[1] / prodBar[2]) * self.fullLen - 1
        local addHalf = math.fmod(barLen, 1) > 0.5 or prodBar[1] == prodBar[2]
        for i = 1, math.floor(barLen), 1 do
            if i == self.fullLen then
                self.gpu:setForeground(table.unpack(bgCol))
                self.gpu:setBackground(table.unpack(fgCol))
                self.gpu:setText(offX + 1, self.offY + self.height - (i + 2), '───────')
                self.gpu:setBackground(table.unpack(bgCol))
                self.gpu:setForeground(table.unpack(fgCol))
            else
                self.gpu:setText(offX, self.offY + self.height - (i + 2), ' ███████ ')
            end
        end

        if addHalf then
            self.gpu:setText(offX + 1, self.offY + self.height - math.floor(barLen + 3), '▄▄▄▄▄▄▄')
        end

        -- draw buffer bar over prod bar
        if bufferBar[2] > 0 then
            local barLen  = (bufferBar[1] / bufferBar[2]) * self.fullLen - 1

            fgCol = {fgCol[1], fgCol[2], fgCol[3], 1}

            for i = 1, math.floor(barLen), 1 do
                if i == self.fullLen then
                    self.gpu:setForeground(table.unpack(bgCol))
                    self.gpu:setBackground(table.unpack(fgCol))
                    self.gpu:setText(offX + 5, self.offY + self.height - (i + 2), '───')
                    self.gpu:setBackground(table.unpack(bgCol))
                    self.gpu:setForeground(table.unpack(fgCol))
                else
                    self.gpu:setText(offX + 5, self.offY + self.height - (i + 2), '▐██')
                end
            end
        end

        -- text
        self.gpu:setText(1 + offX, self.height + 0 + self.offY, math.round(prodBar[1] / prodBar[2] * 100, 2) .. '%')
        self.gpu:setText(1 + offX, self.height + 1 + self.offY, prodBar[1] .. ' / ' .. prodBar[2])
        if bufferBar[2] > 0 then
            self.gpu:setText(1 + offX, self.height + 2 + self.offY, math.round(bufferBar[1], 1))
        end

        self.gpu:setForeground(table.unpack(self.colors.white))

        return self.barWidth
    end,

    drawGroup = function(self, offX, group, last)
        local barIdx  = 0

        offX = offX + 1
        for name, bars in pairs(group) do
            offX = offX + self:drawBar(offX, name, bars[1], bars[2])
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

    draw = function(self, posX, posY)
        if posX < 0 then
            posX = 0
        end

        if posY < 0 then
            posY = 0
        end

        self.offX = posX
        self.offY = posY

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
