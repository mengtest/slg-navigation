local navigation = require "navigation"
local w = 20
local h = 10
local nav = navigation.new(w, h, {
    {4, 0},
    {4, 1},
    {4, 2},
    {4, 3},
    {4, 4},
    {4, 5},
    {4, 6},
    {4, 7},
})

nav.core:dump()
nav.core:dump_connected()

local pos_list = {
    {x = 4, y = 8},
    {x = 4, y = 9}
}
for _, pos in ipairs(pos_list) do
    nav:set_obstacle(pos)
end
nav:quick_remark_area(pos_list, 100)

nav.core:dump()
nav.core:dump_connected()

for _, pos in ipairs(pos_list) do
    nav:unset_obstacle(pos)
end
nav:quick_remark_area(pos_list, 100)

nav.core:dump()
nav.core:dump_connected()
