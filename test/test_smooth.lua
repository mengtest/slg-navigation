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

local function test_find_path_with_smooth(x1, y1, x2, y2, smooth_count)
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s) with smooth_count=%s", x1, y1, x2, y2, smooth_count or "default"))
    local ret = nav:find_path(x1, y1, x2, y2, smooth_count)
    for _, v in ipairs(ret) do
        print(v[1], v[2])
    end
    print("========================")
end

nav:dump()

-- 默认全路径平滑
test_find_path(11.5, 7.5, 9.5, 4.5)

-- 测试smooth_count < 3：不做平滑
test_find_path_with_smooth(11.5, 7.5, 9.5, 4.5, 2)

-- 测试只平滑前3个路点
test_find_path_with_smooth(11.5, 7.5, 9.5, 4.5, 3)

-- 测试只平滑前1个路点（实际上由于n<3所以不平滑）
test_find_path_with_smooth(11.5, 7.5, 9.5, 4.5, 1)
