local navigation = require "navigation.c"
local nav = navigation.new {
    w = 20,
    h = 20,
    obstacle = {
        {8, 6},
        {10, 6},
        {11, 6},
    }
}

local function test_find_path(x1, y1, x2, y2)
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s)", x1, y1, x2, y2))
    local ret = nav:find_path(x1, y1, x2, y2)
    for _, v in ipairs(ret) do
        print(v[1], v[2])
    end
    print("========================")
end

nav:dump()

test_find_path(11.5, 7.5, 9.5, 4.5)
