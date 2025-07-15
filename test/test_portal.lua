local navigation = require "navigation"
local w = 20
local h = 10
local nav = navigation.new(w, h, {
    -- {1, 0},
})

for y = 0, h - 1 do
    nav:set_obstacle { x = 7, y = y }
    nav:set_obstacle { x = 8, y = y }
    nav:set_obstacle { x = 9, y = y }
end

local portal_pos = { x = 8, y = 5 }

nav:set_obstacle { x = 10, y = 6 }
nav:set_obstacle { x = 11, y = 5 }

nav:update_areas()
nav.core:dump()
nav.core:dump_connected()

nav:add_portal(portal_pos)

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

-- test_find_path({ x = 1, y = 1 }, { x = 10, y = 10 })
-- test_find_path({ x = 5, y = 6 }, { x = 10, y = 10 })

-- assert(test_find_path({ x = 1, y = 1 }, { x = 19, y = 1 }) == test_find_path({ x = 1, y = 1 }, { x = 19, y = 1 }))
-- assert(test_find_path({ x = 19, y = 1 }, { x = 1, y = 1 }) == test_find_path({ x = 19, y = 1 }, { x = 1, y = 1 }))

-- assert(test_find_path({ x = 1, y = 1 }, { x = 1, y = 19 }) == test_find_path({ x = 1, y = 1 }, { x = 1, y = 19 }))
-- assert(test_find_path({ x = 0, y = 0 }, { x = 19, y = 19 }) == test_find_path({ x = 0, y = 0 }, { x = 19, y = 19 }))

test_find_path({x = 1, y = 8}, {x = 16, y = 3})