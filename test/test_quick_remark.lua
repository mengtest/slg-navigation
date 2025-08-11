local navigation = require "navigation"
local w = 20
local h = 10
local nav = navigation.new(w, h, {
    {4, 2},
    {4, 3},
    {4, 4},
    {5, 4},
    {6, 4},
    {5, 2},
    {6, 2},
})



nav.core:dump()
nav.core:dump_connected()

local pos_list = {
    {x = 6, y = 3}
}
for _, pos in ipairs(pos_list) do
    nav:set_obstacle(pos)
end
nav:quick_remark_area(pos_list, 10)

