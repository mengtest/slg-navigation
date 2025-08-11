local navigation = require "navigation"
local w = 20
local h = 10
local nav = navigation.new(w, h, {})

for x = 1, w - 2 do
    for y = 1, h - 2 do
        nav:set_obstacle({x = x, y = y})
    end
end

nav:set_obstacle({x = 1, y = 0})
nav:set_obstacle({x = 1, y = 9})


nav.core:dump()
nav.core:dump_connected()

local pos_list = {
    {x = 5, y = 5},
    {x = 5, y = 4},
    {x = 5, y = 3},

    {x = 4, y = 5},
    {x = 4, y = 4},
    {x = 4, y = 3},

    {x = 3, y = 5},
    {x = 3, y = 4},
    {x = 3, y = 3},
}
for _, pos in ipairs(pos_list) do
    nav:unset_obstacle(pos)
end
nav:quick_remark_area(pos_list, 10)

nav.core:dump()
nav.core:dump_connected()