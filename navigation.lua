local navigation_c = require "navigation.c"

local mfloor = math.floor

---@class LuaNavigationPosition
---@field x number
---@field y number

---@class LuaNavigation
local mt = {}
mt.__index = mt

local DIR_OFFSET = { ---@type LuaNavigationPosition[] 顺时针方向
    { x = -1, y = -1 },
    { x = 0,  y = -1 },
    { x = 1,  y = -1 },
    { x = 1,  y = 0 },
    { x = 1,  y = 1 },
    { x = 0,  y = 1 },
    { x = -1, y = 1 },
    { x = -1, y = 0 },
}

function mt:init(w, h, obstacles)
    self.w = w
    self.h = h
    self.core = navigation_c.new {
        w = w,
        h = h,
        obstacle = obstacles,
    }
    self:update_areas()
end

function mt:update_areas()
    self.core:mark_connected()
end

function mt:set_obstacle(pos)
    self.core:add_block(mfloor(pos.x), mfloor(pos.y))
end

function mt:unset_obstacle(pos)
    self.core:clear_block(mfloor(pos.x), mfloor(pos.y))
end

function mt:is_obstacle(pos)
    return self.core:is_block(mfloor(pos.x), mfloor(pos.y))
end

function mt:set_connected_id(pos, id)
    self.core:set_connected_id(mfloor(pos.x), mfloor(pos.y), id)
end

function mt:get_max_connected_id()
    return self.core:get_max_connected_id()
end

---@param left number
---@param right number
---@param bottom number
---@param top number
---@param is_obstacle boolean 是否设置为阻挡
function mt:quick_remark_area(left, right, bottom, top, is_obstacle)
    return self.core:quick_remark_area(left, right, bottom, top, is_obstacle)
end

function mt:get_area_id_by_pos(pos)
    return self.core:get_connected_id(mfloor(pos.x), mfloor(pos.y))
end

function mt:get_neighbor_area_id(pos, max_size)
    -- 从周边格子查找非0的area_id
    local x = mfloor(pos.x)
    local y = mfloor(pos.y)
    for i = 1, max_size do
        for _, dir in pairs(DIR_OFFSET) do
            local nx = x + dir.x * i
            local ny = y + dir.y * i
            if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h then
                local area_id = self.core:get_connected_id(nx, ny)
                if area_id > 0 then
                    return area_id
                end
            end
        end
    end
    return 0
end

function mt:find_path(from_pos, to_pos, check_portal_func, ignore_list, smooth_count)
    ignore_list = ignore_list or {}
    ignore_list[#ignore_list + 1] = from_pos -- 自动忽略起点
    local ignore_map = {}
    for _, pos in pairs(ignore_list) do
        if self.core:is_block(mfloor(pos.x), mfloor(pos.y)) then
            ignore_map[pos] = true
        end
    end
    for pos in pairs(ignore_map) do
        self.core:clear_block(mfloor(pos.x), mfloor(pos.y))
        local next_area_id = self:get_neighbor_area_id(pos, #ignore_list + 1)
        assert(next_area_id > 0, "get_neighbor_area_id failed")
        self:set_connected_id(pos, next_area_id)
    end
    local path
    local from_area_id = self:get_area_id_by_pos(from_pos)
    local to_area_id = self:get_area_id_by_pos(to_pos)
    local ok, errmsg = xpcall(function()
        if from_area_id == to_area_id then
            local cpath = self.core:find_path(from_pos.x, from_pos.y, to_pos.x, to_pos.y, smooth_count) or {}
            path = {}
            for _, pos in ipairs(cpath) do
                path[#path + 1] = {
                    x = pos[1],
                    y = pos[2]
                }
            end
        else
            -- 不同区域无法寻路
            -- print("find_path from_area_id:", from_area_id, "to_area_id:", to_area_id)
            path = {}
        end
    end, debug.traceback)
    if not ok then
        print(errmsg)
    end

    for pos in pairs(ignore_map) do
        self.core:add_block(mfloor(pos.x), mfloor(pos.y))
        self:set_connected_id(pos, 0)
        -- print("find_path set_block:", pos.x, pos.y)
    end
    -- if #path < 2 then
    --     print(string.format("cannot find path (%s, %s) =>(%s, %s)", from_pos.x, from_pos.y, to_pos.x, to_pos.y))
    -- end
    return path
end

local M = {}
function M.new(w, h, obstacles)
    local obj = setmetatable({}, mt)
    obj:init(w, h, obstacles)
    return obj
end

return M
