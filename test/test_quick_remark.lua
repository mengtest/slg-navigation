local navigation = require "navigation"
local w = 20
local h = 10
local nav = navigation.new(w, h, {
    -- {1, 0},
})

for y = 0, h - 1 do
    nav:set_obstacle { x = 6, y = y }
    nav:set_obstacle { x = 13, y = y }
end

nav:update_areas()
nav.core:dump()
nav.core:dump_connected()

nav:add_portal({x = 6, y = 4})
nav:add_portal({x = 13, y = 4})

local function test_find_path(pos1, pos2)
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s)", pos1.x, pos1.y, pos2.x, pos2.y))
    local ret = nav:find_path(pos1, pos2)
    for _, v in ipairs(ret) do
        local pos_str = string.format("(%s, %s)", v.x, v.y)
        assert(not nav:is_obstacle(v), pos_str)
        print(pos_str)
    end
    print("========================")
end

test_find_path({x = 1, y = 8}, {x = 16, y = 3})

for y = 0, 8 do
    local pos = {x = 9, y = y}
    nav:set_obstacle(pos)
    nav:quick_remark_area(pos)
end

nav.core:dump()
nav.core:dump_connected()

test_find_path({x = 1, y = 8}, {x = 16, y = 3})

local pos = {x = 9, y = 9}
nav:set_obstacle(pos)
nav:quick_remark_area(pos)

nav.core:dump()
nav.core:dump_connected()

test_find_path({x = 1, y = 8}, {x = 16, y = 3})
