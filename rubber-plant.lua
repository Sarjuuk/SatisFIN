ExtFiles  = {
    '/include/utils.lua',
    '/include/network.lua',
    '/include/event.lua',
    '/include/scheduler.lua',
    '/include/logger.lua'
}

PlantName = 'rubberPlant'

 -- ----------
 -- load helper funcs
 -- ----------

 if (not fs or not fs.isFile) then
    computer.panic('Expected Filesystem ref not set up!')
 else
     for i, file in pairs(ExtFiles) do
        if not fs.isFile(file) then
            computer.panic(file .. ' not found!')
        else
            fs.doFile(file)
        end
    end
end

Log:write(Log.INFO, 'System started')

Net:init(PlantName)

repeat
    event:update()

    Schedule:update(computer.millis())

until false
