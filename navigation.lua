local navigation_c = require "navigation.c"

local mfloor = math.floor
local sqrt = math.sqrt

---@class LuaNavigationPosition
---@field x number
---@field y number

---@class LuaNavigationNode
---@field cell number
---@field pos LuaNavigationPosition
---@field g number
---@field h number
---@field f number
---@field prev LuaNavigationNode
---@field connected table<LuaNavigationNode, {LuaNavigationPosition[], number}>
---@field disabled boolean 是否不可用

---@class LuaNavigation
local mt = {}
mt.__index = mt

local function pos2cell(self, pos)
    local x = mfloor(pos.x)
    local y = mfloor(pos.y)
    return y * self.w + x
end

local function cell2pos(self, cell)
    return {
        x = cell % self.w + 0.5,
        y = cell // self.w
    }
end

local function create_node(cell, pos)
    ---@class LuaNavigationNode
    local node = {
        cell = cell,
        pos = pos,
        g = 0,
        h = 0,
        f = 0,
        prev = nil,
        connected = {}, -- {node -> {path, length}}
        disabled = false
    }
    return node
end

local function create_graph()
    ---@class LuaNavigationGraph
    local graph = {
        nodes = {}, ---@type {[number]: LuaNavigationNode}
        open_set = {},
        closed_set = {},
    }
    return graph
end

local function create_area(area_id)
    ---@class LuaNavigationArea
    local area = {
        area_id = area_id,
        paths = {},  -- {[from][to] -> path}
        joints = {}, -- {cell -> true}
    }
    return area
end

---@param pos1 LuaNavigationPosition
---@param pos2 LuaNavigationPosition
---@return number
local function calc_distance(pos1, pos2)
    return sqrt((pos1.x - pos2.x) ^ 2 + (pos1.y - pos2.y) ^ 2)
end

---@param path LuaNavigationPosition[]
---@return number
local function calc_path_length(path)
    local len = 0
    for i = 1, #path - 1 do
        local pos1 = path[i]
        local pos2 = path[i + 1]
        len = len + calc_distance(pos1, pos2)
    end
    return len
end

---@generic T
---@param path T[]
---@return T[]
local function reverse_path(path)
    local new = {}
    for i = #path, 1, -1 do
        new[#new + 1] = path[i]
    end
    return new
end

---@param self LuaNavigation
---@param node1 LuaNavigationNode
---@param node2 LuaNavigationNode
local function connect_nodes(self, node1, node2)
    local path = self:find_path(node1.pos, node2.pos)
    -- 只有当路径有效时才建立连接
    if #path >= 2 then
        local length = calc_path_length(path)
        node1.connected[node2] = { path, length }
        node2.connected[node1] = { reverse_path(path), length }
    end
end


---@param self LuaNavigation
---@param node1 LuaNavigationNode
---@param node2 LuaNavigationNode
local function disconnect_nodes(self, node1, node2)
    node1.connected[node2] = nil
    node2.connected[node1] = nil
end

---@param node1 LuaNavigationNode
---@param node2 LuaNavigationNode
local function connect_nodes_cross_area(node1, node2)
    local distance = calc_distance(node1.pos, node2.pos)
    node1.connected[node2] = { { node1.pos, node2.pos }, distance }
    node2.connected[node1] = { { node2.pos, node1.pos }, distance }
end

---@param self LuaNavigation
---@param cell number
---@return LuaNavigationNode
local function get_node(self, cell)
    return self.graph.nodes[cell]
end

---@param self LuaNavigation
---@param area LuaNavigationArea
---@param pos LuaNavigationPosition
local function area_add_joint(self, area, pos)
    local cell = pos2cell(self, pos)
    local nodes = self.graph.nodes
    local node = nodes[cell]
    if not node then
        node = create_node(cell, pos)
        nodes[cell] = node
    end
    area.joints[cell] = node
    for from in pairs(area.joints) do
        for to in pairs(area.joints) do
            if from ~= to then
                local node1 = get_node(self, from)
                local node2 = get_node(self, to)
                if node1 and node2 and not node1.connected[node2] then
                    connect_nodes(self, node1, node2)
                end
            end
        end
    end
    return node
end

---@param self LuaNavigation
---@param area LuaNavigationArea
---@param pos LuaNavigationPosition
local function area_del_joint(self, area, pos)
    local cell = pos2cell(self, pos)
    local nodes = self.graph.nodes
    local node = nodes[cell]
    if node then
        for from in pairs(node.connected) do
            from.connected[node] = nil
        end
    end
    -- 清理节点
    self.graph.nodes[cell] = nil
end

function mt:init(w, h, obstacles)
    self.w = w
    self.h = h
    self.core = navigation_c.new {
        w = w,
        h = h,
        obstacle = obstacles,
    }
    self.portals = {}
    self.areas = {}

    self.graph = create_graph()
    self:update_areas()
end

function mt:update_areas()
    self.core:mark_connected()
end

function mt:set_obstacle(pos)
    local cell = pos2cell(self, pos)
    -- 检查是否有连接点
    for _, area in pairs(self.areas) do
        local node = area.joints[cell]
        if node then
            node.disabled = true
        end
    end
    self.core:add_block(mfloor(pos.x), mfloor(pos.y))
end

function mt:unset_obstacle(pos)
    local cell = pos2cell(self, pos)
    -- 检查是否有连接点
    for _, area in pairs(self.areas) do
        local node = area.joints[cell]
        if node then
            node.disabled = false
        end
    end
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

---@param pos_list LuaNavigationPosition[]
---@param limit_count? number
function mt:quick_remark_area(pos_list, limit_count)
    limit_count = limit_count or 1000
    if #pos_list == 0 then
        return
    end
    if self:get_max_connected_id() <= 0 then
        return
    end
    
    -- 第一步：遍历所有与pos_list相邻的阻挡坐标，找出它们所在的矩形
    local directions = {
        { -1, 0 }, -- 左
        { 1, 0 },  -- 右
        { 0, -1 }, -- 上
        { 0, 1 }   -- 下
    }
    
    local blocked_positions = {}  -- 存储所有相连的阻挡坐标
    local blocked_count = 0
    local visited_blocks = {}  -- 记录已经访问过的阻挡点
    
    local function pos_key(px, py)
        return pos2cell(self, {x = px, y = py})
    end
    
    -- BFS递归查找所有相连的阻挡坐标
    local function find_connected_blocks(start_x, start_y)
        if visited_blocks[pos_key(start_x, start_y)] then
            return
        end
        
        local queue = {}
        local head = 1
        
        queue[#queue + 1] = { start_x, start_y }
        visited_blocks[pos_key(start_x, start_y)] = true
        
        while head <= #queue do
            local cur = queue[head]
            head = head + 1
            local cx, cy = cur[1], cur[2]
            
            -- 将当前阻挡点加入结果
            local key = pos_key(cx, cy)
            if not blocked_positions[key] then
                blocked_positions[key] = { cx, cy }
                blocked_count = blocked_count + 1
                
                -- 检查是否到达地图边界
                if cx == 0 or cx == self.w - 1 or cy == 0 or cy == self.h - 1 then
                    print(string.format("[quick_remark_area] 阻挡格子 (%d,%d) 到达地图边界，执行完整更新", cx, cy))
                    self:update_areas()
                    return true  -- 返回true表示达到边界
                end
                
                -- 检查是否超过限制
                if blocked_count >= limit_count then
                    print(string.format("[quick_remark_area] 相连阻挡数量 %d 达到限制 %d，执行完整更新", blocked_count, limit_count))
                    self:update_areas()
                    return true  -- 返回true表示达到限制
                end
            end
            
            -- 检查四个方向的相邻点
            for _, dir in ipairs(directions) do
                local nx, ny = cx + dir[1], cy + dir[2]
                local nkey = pos_key(nx, ny)
                
                -- 检查边界和是否已访问
                if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h and
                   not visited_blocks[nkey] then
                    -- 如果是阻挡点，加入队列继续搜索
                    if self.core:is_block(nx, ny) then
                        visited_blocks[nkey] = true
                        queue[#queue + 1] = { nx, ny }
                    end
                end
            end
        end
        
        return false  -- 返回false表示未达到限制
    end
    
    -- 遍历pos_list中的每个位置，找到相邻的阻挡点作为起始点
    for _, pos in ipairs(pos_list) do
        local x = mfloor(pos.x)
        local y = mfloor(pos.y)
        
        -- 检查这个位置周围的4个方向
        for _, dir in ipairs(directions) do
            local nx, ny = x + dir[1], y + dir[2]
            
            -- 检查边界
            if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h then
                -- 如果是阻挡点且未访问过，开始BFS搜索整个相连区域
                if self.core:is_block(nx, ny) and not visited_blocks[pos_key(nx, ny)] then
                    local limit_reached = find_connected_blocks(nx, ny)
                    if limit_reached then
                        return  -- 如果达到限制，直接返回
                    end
                end
            end
        end
    end
    
    -- 找出所有阻挡坐标的矩形边界
    local blocked_coords = {}
    for _, coord in pairs(blocked_positions) do
        blocked_coords[#blocked_coords + 1] = coord
    end
    
    if #blocked_coords == 0 then
        print("[quick_remark_area] 没有找到相邻的阻挡坐标")
        return
    end
    
    -- 计算矩形边界
    local min_x, max_x = blocked_coords[1][1], blocked_coords[1][1]
    local min_y, max_y = blocked_coords[1][2], blocked_coords[1][2]
    
    for _, coord in ipairs(blocked_coords) do
        min_x = math.min(min_x, coord[1])
        max_x = math.max(max_x, coord[1])
        min_y = math.min(min_y, coord[2])
        max_y = math.max(max_y, coord[2])
    end
    
    print(string.format("[quick_remark_area] 找到 %d 个相邻阻挡坐标", #blocked_coords))
    print(string.format("[quick_remark_area] 阻挡坐标矩形区域: (%d,%d) - (%d,%d)", 
        min_x, min_y, max_x, max_y))
    
    -- 打印所有阻挡坐标详情
    print("[quick_remark_area] 阻挡坐标列表:")
    for i, coord in ipairs(blocked_coords) do
        print(string.format("  [%d] (%d,%d)", i, coord[1], coord[2]))
    end
    
    -- 第二步：在矩形区域内进行重新分区
    -- 扩展矩形区域，确保包含足够的上下文
    local expand = 3
    local region_min_x = math.max(0, min_x - expand)
    local region_max_x = math.min(self.w - 1, max_x + expand)
    local region_min_y = math.max(0, min_y - expand)
    local region_max_y = math.min(self.h - 1, max_y + expand)
    
    print(string.format("[quick_remark_area] 重新分区区域: (%d,%d) - (%d,%d)", 
        region_min_x, region_min_y, region_max_x, region_max_y))
    
    -- 记录边界格子的原始分区ID（这些ID不允许改变）
    local boundary_ids = {}
    local is_boundary = function(px, py)
        return px == region_min_x or px == region_max_x or py == region_min_y or py == region_max_y
    end
    
    -- 保存边界格子的分区ID
    local boundary_count = 0
    for py = region_min_y, region_max_y do
        for px = region_min_x, region_max_x do
            if is_boundary(px, py) and not self.core:is_block(px, py) then
                local id = self.core:get_connected_id(px, py)
                boundary_ids[pos_key(px, py)] = id
                boundary_count = boundary_count + 1
                print(string.format("[quick_remark_area] 边界格子 (%d,%d) ID: %d", px, py, id))
            end
        end
    end
    print(string.format("[quick_remark_area] 保存了 %d 个边界格子ID", boundary_count))
    
    -- 清空区域内所有非边界格子的分区ID
    for py = region_min_y + 1, region_max_y - 1 do
        for px = region_min_x + 1, region_max_x - 1 do
            if not self.core:is_block(px, py) then
                self.core:set_connected_id(px, py, 0)
            end
        end
    end
    
    -- 参照lnav_mark_connected算法进行flood fill分区
    local visited = {}
    local new_connected_id = self.core:get_max_connected_id() + 1
    
    local function flood_fill(start_x, start_y, area_id)
        local queue = {}
        local head = 1
        
        queue[#queue + 1] = { start_x, start_y }
        visited[pos_key(start_x, start_y)] = true
        self.core:set_connected_id(start_x, start_y, area_id)
        
        while head <= #queue do
            local cur = queue[head]
            head = head + 1
            local cx, cy = cur[1], cur[2]
            
            -- 检查四个方向
            for _, dir in ipairs(directions) do
                local nx, ny = cx + dir[1], cy + dir[2]
                local nkey = pos_key(nx, ny)
                
                -- 检查边界和是否已访问
                if nx >= region_min_x and nx <= region_max_x and 
                   ny >= region_min_y and ny <= region_max_y and
                   not visited[nkey] and not self.core:is_block(nx, ny) then
                    
                    -- 如果是边界格子，使用其原始ID，但仍要继续扩散
                    if is_boundary(nx, ny) then
                        local boundary_id = boundary_ids[nkey]
                        if boundary_id and boundary_id > 0 then
                            -- 如果边界格子的ID与当前扩散的ID相同，继续扩散
                            if boundary_id == area_id then
                                self.core:set_connected_id(nx, ny, boundary_id)
                                visited[nkey] = true
                                queue[#queue + 1] = { nx, ny }
                            else
                                -- 不同ID的边界格子，不扩散
                                self.core:set_connected_id(nx, ny, boundary_id)
                                visited[nkey] = true
                            end
                        end
                    else
                        -- 内部格子，使用当前area_id
                        visited[nkey] = true
                        self.core:set_connected_id(nx, ny, area_id)
                        queue[#queue + 1] = { nx, ny }
                    end
                end
            end
        end
    end
    
    -- 从边界格子开始扩散，使用边界格子的原始ID
    for py = region_min_y, region_max_y do
        for px = region_min_x, region_max_x do
            if is_boundary(px, py) and not self.core:is_block(px, py) and not visited[pos_key(px, py)] then
                local boundary_id = boundary_ids[pos_key(px, py)]
                if boundary_id and boundary_id > 0 then
                    flood_fill(px, py, boundary_id)
                end
            end
        end
    end
    
    -- 处理内部未被边界扩散覆盖的连通区域，分配新的ID
    local new_regions_count = 0
    for py = region_min_y + 1, region_max_y - 1 do
        for px = region_min_x + 1, region_max_x - 1 do
            if not self.core:is_block(px, py) and not visited[pos_key(px, py)] then
                print(string.format("[quick_remark_area] 发现新连通区域起点 (%d,%d), 分配ID: %d", px, py, new_connected_id))
                flood_fill(px, py, new_connected_id)
                new_connected_id = new_connected_id + 1
                new_regions_count = new_regions_count + 1
            end
        end
    end
    
    print(string.format("[quick_remark_area] 重新分区完成，创建了 %d 个新连通区域", new_regions_count))
end

function mt:get_area_id_by_pos(pos)
    return self.core:get_connected_id(mfloor(pos.x), mfloor(pos.y))
end

function mt:get_area(area_id)
    local area = self.areas[area_id]
    if not area then
        area = create_area(area_id)
        self.areas[area_id] = area
    end
    return area
end

local function find_walkable_area_around(self, center_pos, max_size)
    local cx = mfloor(center_pos.x)
    local cy = mfloor(center_pos.y)
    for i = 0, max_size do
        for j = 0, max_size do
            if not self.core:is_block(cx + i, cy + j) then
                return self:get_area_id_by_pos(center_pos)
            end
        end
    end
end

---@param center_pos LuaNavigationPosition
---@param camp? number
---@param max_size? number
---@param joints? LuaNavigationPosition[]
function mt:add_portal(center_pos, camp, max_size, joints)
    if not self:is_obstacle(center_pos) then
        return
    end
    local cell = pos2cell(self, center_pos)
    ---@class LuaNavigationPortal
    local portal = {
        pos = center_pos, ---@type LuaNavigationPosition
        cell = cell, ---@type number
        camp = camp, ---@type number?
        joints = {} ---@type LuaNavigationPosition[]
    }
    self.portals[cell] = portal
    local cx = mfloor(center_pos.x)
    local cy = mfloor(center_pos.y)
    max_size = max_size or 10
    if joints then
        -- 从关节点向中心点反方向寻找空白格
        for _, pos in pairs(joints) do
            local direction_x = pos.x - center_pos.x
            local direction_y = pos.y - center_pos.y
            local step_x = direction_x ~= 0 and direction_x / math.abs(direction_x) or 0
            local step_y = direction_y ~= 0 and direction_y / math.abs(direction_y) or 0
            local current_x = pos.x
            local current_y = pos.y

            while math.abs(current_x - center_pos.x) <= max_size and math.abs(current_y - center_pos.y) <= max_size do
                if not self.core:is_block(mfloor(current_x), mfloor(current_y)) then
                    table.insert(portal.joints, { x = current_x + 0.5, y = current_y + 0.5 })
                    break
                end
                current_x = current_x + step_x
                current_y = current_y + step_y
            end
        end
    else
        for i = 1, max_size // 2 do
            if not self.core:is_block(cx - i, cy) and not self.core:is_block(cx + i, cy) then
                portal.joints = {
                    { x = cx - i + 0.5, y = cy + 0.5 },
                    { x = cx + i + 0.5, y = cy + 0.5 },
                }
                break
            end
            if not self.core:is_block(cx, cy - i) and not self.core:is_block(cx, cy + i) then
                portal.joints = {
                    { x = cx + 0.5, y = cy - i + 0.5 },
                    { x = cx + 0.5, y = cy + i + 0.5 },
                }
                break
            end
        end
    end
    local last_node
    for _, pos in pairs(portal.joints) do
        local area_id = self:get_area_id_by_pos(pos)
        local area = self:get_area(area_id)
        local node = area_add_joint(self, area, pos)
        if last_node then
            connect_nodes_cross_area(node, last_node)
        else
            last_node = node
        end
    end
end

function mt:del_portal(pos)
    local cell = pos2cell(self, pos)
    local portal = self.portals[cell]
    if portal then
        for _, joint in pairs(portal.joints) do
            local area_id = self:get_area_id_by_pos(joint)
            local area = self:get_area(area_id)
            area_del_joint(self, area, joint)
        end
        self.portals[cell] = nil
    else
        print("not found portal", cell)
    end
end

local function connect_to_area(area, node)
    for _, joint in pairs(area.joints) do
        if not joint.disabled then
            local distance = calc_distance(node.pos, joint.pos)
            node.connected[joint] = { { node.pos, joint.pos }, distance }
            joint.connected[node] = { { joint.pos, node.pos }, distance }
        end
    end
end

local function disconnect_to_area(area, node)
    for _, joint in pairs(area.joints) do
        node.connected[joint] = nil
        joint.connected[node] = nil
    end
end

local function merge_path(path1, path2)
    for i = 1, #path2 - 1 do
        path1[#path1 + 1] = { x = path2[i].x, y = path2[i].y }
    end
end

local function table_2_string(tbl)
    if not tbl then
        return nil
    end

    local set = {}
    local function traverse_tbl(tmp_tbl)
        local t = {}
        for k, v in pairs(tmp_tbl) do
            local s
            if type(v) == "table" then
                if not set[v] then
                    set[v] = true
                    s = string.format("%s:%s", k, traverse_tbl(v))
                end
            else
                s = string.format("%s:%s", k, v)
            end
            t[#t + 1] = s
        end
        return string.format("[%s]", table.concat(t, ", "))
    end
    local result = traverse_tbl(tbl)
    return result
end

---@param self LuaNavigation
local function find_path_cross_area(self, src_area_id, src_pos, dst_area_id, dst_pos)
    local graph = self.graph
    local open_set = {}
    local closed_set = {}

    local src_cell = pos2cell(self, src_pos)
    local dst_cell = pos2cell(self, dst_pos)
    local src_node = create_node(src_cell, src_pos)
    local dst_node = create_node(dst_cell, dst_pos)
    local src_area = self:get_area(src_area_id)
    local dst_area = self:get_area(dst_area_id)

    connect_to_area(src_area, src_node)
    connect_to_area(dst_area, dst_node)

    local path = {}

    local ok, errmsg = xpcall(function()
        local function add_to_open_set(node, prev)
            if open_set[node] or closed_set[node] then
                return
            end
            open_set[node] = true
            node.prev = prev
            if prev then
                node.g = prev.g + calc_distance(node.pos, prev.pos)
            else
                node.g = 0
            end
            node.h = calc_distance(node.pos, dst_pos)
            node.f = node.g + node.h
        end
        add_to_open_set(src_node)
        while next(open_set) do
            local cur_node
            for node in pairs(open_set) do
                if not cur_node then
                    cur_node = node
                else
                    if node.f < cur_node.f then
                        cur_node = node
                    end
                end
            end
            open_set[cur_node] = nil
            closed_set[cur_node] = true
            for node in pairs(cur_node.connected) do
                if not node.disabled and not closed_set[node] and not open_set[node] then
                    add_to_open_set(node, cur_node)
                end
            end
        end

        if not dst_node.prev then
            return {}
        end
        local node_path = {} ---@type LuaNavigationNode[]
        local node = dst_node
        while true do
            node_path[#node_path + 1] = node
            if node == src_node then
                break
            end
            node = node.prev
        end

        node_path = reverse_path(node_path)
        local first = node_path[1]
        local second = node_path[2]
        first.connected[second][1] = self:find_path(first.pos, second.pos)
        local last = node_path[#node_path]
        local last_second = node_path[#node_path - 1]
        last_second.connected[last][1] = self:find_path(last_second.pos, last.pos)

        for i = 1, #node_path - 1 do
            local cur_node = node_path[i]
            local next_node = node_path[i + 1]
            local part = cur_node.connected[next_node][1]
            merge_path(path, part)
        end
        path[#path + 1] = last.pos
    end, debug.traceback)
    if not ok then
        print(errmsg)
    end

    disconnect_to_area(src_area, src_node)
    disconnect_to_area(dst_area, dst_node)

    return path
end

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

---@param self LuaNavigation
---@param pos LuaNavigationPosition
---@param max_size number
local function find_nearest_joint(self, pos, max_size)
    local tmp_pos = { x = pos.x, y = pos.y }
    local nodes = self.graph.nodes
    for i = 1, max_size do
        for _, dir in pairs(DIR_OFFSET) do
            tmp_pos.x = pos.x + dir.x * i
            tmp_pos.y = pos.y + dir.y * i
            local cell = pos2cell(self, tmp_pos)
            local node = nodes[cell]
            if node then
                return node.pos
            end
        end
    end
end

local function find_path_start_in_portal(self, from_area_id, from_pos, to_area_id, to_pos)
    local joint_pos = find_nearest_joint(self, from_pos, 5)
    if not joint_pos then
        return {}
    end
    local path = find_path_cross_area(self, self:get_area_id_by_pos(joint_pos), joint_pos, to_area_id, to_pos)
    if #path < 2 then
        return path
    end
    local first_point = path[1]
    first_point.x = from_pos.x
    first_point.y = from_pos.y
    return path
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

function mt:find_path(from_pos, to_pos, check_portal_func, ignore_list)
    ignore_list = ignore_list or { } 
    ignore_list[#ignore_list + 1] = from_pos -- 自动忽略起点
    local ignore_map = {}
    for _, pos in pairs(ignore_list) do
        if self.core:is_block(mfloor(pos.x), mfloor(pos.y)) then
            ignore_map[pos] = true
        end
    end
    for pos in pairs(ignore_map) do
        self.core:clear_block(mfloor(pos.x), mfloor(pos.y))
        self:set_connected_id(pos, self:get_neighbor_area_id(pos, #ignore_list))
    end
    local path
    local from_area_id = self:get_area_id_by_pos(from_pos)
    local to_area_id = self:get_area_id_by_pos(to_pos)
    local ok, errmsg = xpcall(function()
        if from_area_id == to_area_id then
            local cpath = self.core:find_path(from_pos.x, from_pos.y, to_pos.x, to_pos.y) or {}
            path = {}
            for _, pos in ipairs(cpath) do
                path[#path + 1] = {
                    x = pos[1],
                    y = pos[2]
                }
            end
        elseif from_area_id == 0 then
            path = find_path_start_in_portal(self, from_area_id, from_pos, to_area_id, to_pos)
        else
            path = find_path_cross_area(self, from_area_id, from_pos, to_area_id, to_pos)
        end
    end, debug.traceback)
    if not ok then
        print(errmsg)
    end

    for pos in pairs(ignore_map) do
        self.core:add_block(mfloor(pos.x), mfloor(pos.y))
        self:set_connected_id(pos, 0)
    end
    if #path < 2 then
        print(string.format("cannot find path (%s, %s) =>(%s, %s)", from_pos.x, from_pos.y, to_pos.x, to_pos.y))
    end
    return path
end

local M = {}
function M.new(w, h, obstacles)
    local obj = setmetatable({}, mt)
    obj:init(w, h, obstacles)
    return obj
end

return M
