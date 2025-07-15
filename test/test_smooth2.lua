local navigation = require "navigation"
local w = 20
local h = 10
local nav = navigation.new(w, h, {
    {1, 0},
})

nav.core:dump()

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

test_find_path({x = 0, y = 0}, {x = 8, y = 6})

nav:unset_obstacle({x = 1, y = 0})
nav:set_obstacle({x = 12, y = 4})
nav.core:dump()

test_find_path({x = 11, y = 4}, {x = 16, y = 3})