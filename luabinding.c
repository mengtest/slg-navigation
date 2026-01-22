#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "fibheap.h"
#include "jps.h"
#include "map.h"
#include "smooth.h"

#define MT_NAME ("_nav_metatable")

static inline int getfield(lua_State* L, const char* f) {
    if (lua_getfield(L, -1, f) != LUA_TNUMBER) {
        return luaL_error(L, "invalid type %s", f);
    }
    int v = lua_tointeger(L, -1);
    lua_pop(L, 1);
    return v;
}

static inline int setobstacle(lua_State* L, Map* m, int x, int y) {
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITSET(m->m, m->width * y + x);
    return 0;
}

static void push_path_to_istack(lua_State* L, Map* m) {
    lua_newtable(L);
    int i, x, y;
    int num = 1;
    for (i = m->ipath_len - 1; i >= 0; i--) {
        pos2xy(m, m->ipath[i], &x, &y);
        // printf("pos:%d x:%d y:%d\n", m->ipath[i], x, y);
        lua_newtable(L);
        lua_pushinteger(L, x);
        lua_rawseti(L, -2, 1);
        lua_pushinteger(L, y);
        lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, num++);
    }
}

static void push_fpos(lua_State* L, float fx, float fy, int num) {
    lua_newtable(L);
    lua_pushnumber(L, fx);
    lua_rawseti(L, -2, 1);
    lua_pushnumber(L, fy);
    lua_rawseti(L, -2, 2);
    lua_rawseti(L, -2, num);
}

static void push_path_to_fstack(lua_State* L,
                                Map* m,
                                float fx1,
                                float fy1,
                                float fx2,
                                float fy2) {
    lua_newtable(L);
    int i, ix, iy;
    int num = 1;
    if (m->ipath_len < 2) {
        return;
    }

    push_fpos(L, fx1, fy1, num++);
    pos2xy(m, m->ipath[m->ipath_len - 2], &ix, &iy);

    for (i = m->ipath_len - 2; i >= 1; i--) {
        pos2xy(m, m->ipath[i], &ix, &iy);
        push_fpos(L, ix + 0.5, iy + 0.5, num++);
    }

    push_fpos(L, fx2, fy2, num++);
}

static int insert_mid_jump_point(Map* m, int cur, int father) {
    int w = m->width;
    int dx = cur % w - father % w;
    int dy = cur / w - father / w;
    if (dx == 0 || dy == 0) {
        return 0;
    }
    if (dx < 0) {
        dx = -dx;
    }
    if (dy < 0) {
        dy = -dy;
    }
    if (dx == dy) {
        return 0;
    }
    int span = dx;
    if (dy < dx) {
        span = dy;
    }
    int mx = 0, my = 0;
    if (cur % w < father % w && cur / w < father / w) {
        mx = father % w - span;
        my = father / w - span;
    } else if (cur % w < father % w && cur / w > father / w) {
        mx = father % w - span;
        my = father / w + span;
    } else if (cur % w > father % w && cur / w < father / w) {
        mx = father % w + span;
        my = father / w - span;
    } else if (cur % w > father % w && cur / w > father / w) {
        mx = father % w + span;
        my = father / w + span;
    }
    push_pos_to_ipath(m, xy2pos(m, mx, my));
    return 1;
}

static void flood_mark(struct map *m, int pos, int connected_num, int limit) {
    char *visited = m->visited;
    if (visited[pos]) {
        return;
    }
    int *queue = m->queue;
    memset(queue, 0, limit * sizeof(int));
    int pop_i = 0, push_i = 0;
    visited[pos] = 1;
    m->connected[pos] = connected_num;
    queue[push_i++] = pos;

#define CHECK_POS(n) do { \
    if (!BITTEST(m->m, n)) { \
        if (!visited[n]) { \
            visited[n] = 1; \
            m->connected[n] = connected_num; \
            queue[push_i++] = n; \
        } \
    } \
} while(0);
    int cur, left;
    while (pop_i < push_i) {
        cur = queue[pop_i++];
        left = cur % m->width;
        if (left != 0) {
            CHECK_POS(cur - 1);
        }
        if (left != m->width - 1) {
            CHECK_POS(cur + 1);
        }
        if (cur >= m->width) {
            CHECK_POS(cur - m->width);
        }
        if (cur < limit - m->width) {
            CHECK_POS(cur + m->width);
        }
    }
#undef CHECK_POS
}

static int lnav_add_block(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITSET(m->m, m->width * y + x);
    m->connected[m->width * y + x] = 0;
    return 0;
}

static int lnav_is_block(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    int block = BITTEST(m->m, m->width * y + x);
    lua_pushboolean(L, block);
    return 1;
}

static int lnav_get_connected_id(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    lua_pushnumber(L, m->connected[m->width * y + x]);
    return 1;
}

static int lnav_set_connected_id(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    int connected_id = luaL_checkinteger(L, 4);
    
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    
    if (!m->mark_connected) {
        luaL_error(L, "Map has not been marked for connected areas, mark_connected: %d", m->mark_connected);
    }
    
    m->connected[m->width * y + x] = connected_id;
    if (connected_id > m->mark_connected) {
        m->mark_connected = connected_id;
    }
    return 0;
}

static int lnav_get_max_connected_id(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int max_id = m->mark_connected;
    lua_pushinteger(L, max_id);
    return 1;
}

static int lnav_blockset(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);
    int i = 1;
    while (lua_geti(L, -1, i) == LUA_TTABLE) {
        lua_geti(L, -1, 1);
        int x = lua_tointeger(L, -1);
        lua_geti(L, -2, 2);
        int y = lua_tointeger(L, -1);
        setobstacle(L, m, x, y);
        m->connected[m->width * y + x] = 0;
        lua_pop(L, 3);
        ++i;
    }
    return 0;
}

static int lnav_clear_block(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITCLEAR(m->m, m->width * y + x);
    return 0;
}

static int lnav_clear_allblock(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int i;
    for (i = 0; i < m->width * m->height; i++) {
        BITCLEAR(m->m, i);
    }
    return 0;
}

static int lnav_mark_connected(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);

    // m->mark_connected = 1;
    int len = m->width * m->height;
    memset(m->connected, 0, len * sizeof(int));
    memset(m->visited, 0, len * sizeof(char));
    int i, connected_num = 0;
    for (i = 0; i < len; i++) {
        if (!m->visited[i] && !BITTEST(m->m, i)) {
            flood_mark(m, i, ++connected_num, len);
        }
    }

    m->mark_connected = connected_num > 0 ? connected_num : 1;
    return 0;
}

static int lnav_dump_connected(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    printf("dump map connected state!!!!!!\n");
    if (!m->mark_connected) {
        printf("have not mark connected.\n");
        return 0;
    }
    
    // 获取可选的边界参数
    int left = 0, right = m->width - 1, bottom = 0, top = m->height - 1;
    if (lua_gettop(L) >= 2 && !lua_isnil(L, 2)) left = (int)luaL_checknumber(L, 2);
    if (lua_gettop(L) >= 3 && !lua_isnil(L, 3)) right = (int)luaL_checknumber(L, 3);
    if (lua_gettop(L) >= 4 && !lua_isnil(L, 4)) bottom = (int)luaL_checknumber(L, 4);
    if (lua_gettop(L) >= 5 && !lua_isnil(L, 5)) top = (int)luaL_checknumber(L, 5);
    
    // 边界检查
    if (left < 0) left = 0;
    if (right >= m->width) right = m->width - 1;
    if (bottom < 0) bottom = 0;
    if (top >= m->height) top = m->height - 1;
    
    if (left > right || bottom > top) {
        printf("invalid range: left=%d, right=%d, bottom=%d, top=%d\n", left, right, bottom, top);
        return 0;
    }
    
    // 按行打印，确保换行正确
    for (int y = bottom; y <= top; y++) {
        for (int x = left; x <= right; x++) {
            int pos = y * m->width + x;
            int mark = m->connected[pos];
            if (mark > 0) {
                printf("%d ", mark);
            } else {
                printf("* ");
            }
        }
        printf("\n"); // 每行结束后换行
    }
    return 0;
}

static int lnav_dump(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    printf("dump map state!!!!!!\n");
    
    // 获取可选的边界参数
    int left = 0, right = m->width - 1, bottom = 0, top = m->height - 1;
    if (lua_gettop(L) >= 2 && !lua_isnil(L, 2)) left = (int)luaL_checknumber(L, 2);
    if (lua_gettop(L) >= 3 && !lua_isnil(L, 3)) right = (int)luaL_checknumber(L, 3);
    if (lua_gettop(L) >= 4 && !lua_isnil(L, 4)) bottom = (int)luaL_checknumber(L, 4);
    if (lua_gettop(L) >= 5 && !lua_isnil(L, 5)) top = (int)luaL_checknumber(L, 5);
    
    // 边界检查
    if (left < 0) left = 0;
    if (right >= m->width) right = m->width - 1;
    if (bottom < 0) bottom = 0;
    if (top >= m->height) top = m->height - 1;
    
    if (left > right || bottom > top) {
        printf("invalid range: left=%d, right=%d, bottom=%d, top=%d\n", left, right, bottom, top);
        return 0;
    }
    
    // 按行打印，确保换行正确
    for (int y = bottom; y <= top; y++) {
        for (int x = left; x <= right; x++) {
            int pos = y * m->width + x;
            int mark = 0;
            if (BITTEST(m->m, pos)) {
                printf("* ");
                mark = 1;
            }
            if (pos == m->start) {
                printf("S ");
                mark = 1;
            }
            if (pos == m->end) {
                printf("E ");
                mark = 1;
            }
            if (!mark) {
                printf(". ");
            }
        }
        printf("\n"); // 每行结束后换行
    }
    return 0;
}

static int lnav_quick_remark_area(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int left = (int)luaL_checknumber(L, 2);
    int right = (int)luaL_checknumber(L, 3);
    int bottom = (int)luaL_checknumber(L, 4);
    int top = (int)luaL_checknumber(L, 5);
    int is_obstacle = lua_toboolean(L, 6);
    
    // 边界检查
    if (left < 0) left = 0;
    if (right >= m->width) right = m->width - 1;
    if (bottom < 0) bottom = 0;
    if (top >= m->height) top = m->height - 1;
    
    if (left > right || bottom > top) {
        return 0; // 无效范围
    }
    
    // 第一步：设置矩形范围内的阻挡/非阻挡状态
    for (int y = bottom; y <= top; y++) {
        for (int x = left; x <= right; x++) {
            int pos = y * m->width + x;
            if (is_obstacle) {
                BITSET(m->m, pos);
                m->connected[pos] = 0;
            } else {
                BITCLEAR(m->m, pos);
            }
        }
    }

    // printf("quick_remark_area: left=%d, right=%d, bottom=%d, top=%d, is_obstacle=%d\n", left, right, bottom, top, is_obstacle);

    // 第二步：收集outline格子
    int outline_count = 0;
    memset(m->remark_outline, 0, MAX_REMARK_OUTLINE_COUNT * sizeof(int));
    if (outline_count >= MAX_REMARK_OUTLINE_COUNT) {
        luaL_error(L, "outline_count >= MAX_REMARK_OUTLINE_COUNT");
    }
    
    int pos = 0;
    // 上边
    if (bottom > 0) {
        for (int x = (left > 0 ? left - 1 : 0); x <= (right < m->width - 1 ? right + 1 : m->width - 1); x++) {
            pos = (bottom - 1) * m->width + x;
            m->remark_outline[outline_count++] = pos;
        }
    }
    
    // 下边
    if (top < m->height - 1) {
        for (int x = (left > 0 ? left - 1 : 0); x <= (right < m->width - 1 ? right + 1 : m->width - 1); x++) {
            pos = (top + 1) * m->width + x;
            m->remark_outline[outline_count++] = pos;
        }
    }
    
    // 左边
    if (left > 0) {
        for (int y = bottom; y <= top; y++) {
            pos = y * m->width + (left - 1);
            m->remark_outline[outline_count++] = pos;
        }
    }
    
    // 右边
    if (right < m->width - 1) {
        for (int y = bottom; y <= top; y++) {
            pos = y * m->width + (right + 1);
            m->remark_outline[outline_count++] = pos;
        }
    }

    int target_area_id = 0;
    // 第三步：检查outline格子状态
    int blocked_count = 0, walkable_count = 0;
    for (int i = 0; i < outline_count; i++) {
        if (BITTEST(m->m, m->remark_outline[i])) {
            blocked_count++;
        } else {
            walkable_count++;
            target_area_id = m->connected[m->remark_outline[i]];
        }
    }

    // 先处理矩形内的格子（如果是非阻挡模式）
    if (!is_obstacle) {
        if (target_area_id == 0) {
            target_area_id = ++m->mark_connected;
        }
        for (int y = bottom; y <= top; y++) {
            for (int x = left; x <= right; x++) {
                int pos = y * m->width + x;
                m->connected[pos] = target_area_id;
            }
        }
    }

    // 如果状态统一，直接返回
    if (blocked_count == 0 || walkable_count == 0) {
        return 0;
    }
    
    // 第四步：区域遍历和ID分配
    int len = m->width * m->height;
    memset(m->visited, 0, len * sizeof(char));
    
    int new_area_id = m->mark_connected + 1;
    
    // 第四步：从outline可行走格子开始遍历区域并设置area_id

    // 遍历所有outline的可行走格子
    for (int i = 0; i < outline_count; i++) {
        int pos = m->remark_outline[i];
        if (!BITTEST(m->m, pos) && !m->visited[pos]) {
            flood_mark(m, pos, new_area_id++, len);
        }
    }
    
    if (new_area_id > m->mark_connected + 1) {
        m->mark_connected = new_area_id - 1;
    }
    
    return 0;
}

static int gc(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    free(m->comefrom);
    free(m->open_set_map);
    if (m->mark_connected) {
        free(m->connected);
    }
    free(m->queue);
    free(m->visited);
    free(m->remark_outline);
    free(m->ipath);
    return 0;
}

static void form_ipath(Map* m, int last) {
    int pos = last;
    m->ipath_len = 0;

    while (m->comefrom[pos] != -1) {
        push_pos_to_ipath(m, pos);
        insert_mid_jump_point(m, pos, m->comefrom[pos]);
        pos = m->comefrom[pos];
    }
    push_pos_to_ipath(m, m->start);
}

static int lnav_check_line_walkable(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    float x1 = luaL_checknumber(L, 2);
    float y1 = luaL_checknumber(L, 3);
    float x2 = luaL_checknumber(L, 4);
    float y2 = luaL_checknumber(L, 5);
    lua_pushboolean(L, find_line_obstacle(m, x1, y1, x2, y2) < 0);
    return 1;
}

static int lnav_find_path(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    float fx1 = luaL_checknumber(L, 2);
    float fy1 = luaL_checknumber(L, 3);
    int x = fx1;
    int y = fy1;
    if (check_in_map(x, y, m->width, m->height)) {
        m->start = m->width * y + x;
    } else {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    float fx2 = luaL_checknumber(L, 4);
    float fy2 = luaL_checknumber(L, 5);
    x = fx2;
    y = fy2;
    if (check_in_map(x, y, m->width, m->height)) {
        m->end = m->width * y + x;
    } else {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    // 新增：平滑路点数量参数，默认为整条路径
    int smooth_count = luaL_optinteger(L, 6, INT_MAX);
    
    if(floor(fx1) == floor(fx2) && floor(fy1) == floor(fy2)) {
        lua_newtable(L);
        push_fpos(L, fx1, fy1, 1);
        push_fpos(L, fx2, fy2, 2);
        return 1;
    }
    if (BITTEST(m->m, m->start)) {
        // luaL_error(L, "start pos(%d,%d) is in block", m->start % m->width,
        //            m->start / m->width);
        return 0;
    }
    if (BITTEST(m->m, m->end)) {
        // luaL_error(L, "end pos(%d,%d) is in block", m->end % m->width,
        //            m->end / m->width);
        return 0;
    }
    if (m->connected[m->start] != m->connected[m->end]) {
        return 0;
    }
    int start_pos = jps_find_path(m);
    if (start_pos >= 0) {
        form_ipath(m, start_pos);
        smooth_path(m, smooth_count);
        push_path_to_fstack(L, m, fx1, fy1, fx2, fy2);
        return 1;
    }
    return 0;
}

static int lnav_find_path_by_grid(lua_State* L) {
    Map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (check_in_map(x, y, m->width, m->height)) {
        m->start = m->width * y + x;
    } else {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    x = luaL_checkinteger(L, 4);
    y = luaL_checkinteger(L, 5);
    if (check_in_map(x, y, m->width, m->height)) {
        m->end = m->width * y + x;
    } else {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    if (BITTEST(m->m, m->start)) {
        luaL_error(L, "start pos(%d,%d) is in block", m->start % m->width,
                   m->start / m->width);
        return 0;
    }
    if (BITTEST(m->m, m->end)) {
        luaL_error(L, "end pos(%d,%d) is in block", m->end % m->width,
                   m->end / m->width);
        return 0;
    }
    int without_smooth = lua_toboolean(L, 6);
    int smooth_count = luaL_optinteger(L, 7, INT_MAX);
    int start_pos = jps_find_path(m);
    if (start_pos >= 0) {
        form_ipath(m, start_pos);
        if (!without_smooth) {
            smooth_path(m, smooth_count);
        }
        push_path_to_istack(L, m);
        return 1;
    }
    return 0;
}

static int lmetatable(lua_State* L) {
    if (luaL_newmetatable(L, MT_NAME)) {
        luaL_Reg l[] = {{"add_block", lnav_add_block},
                        {"add_blockset", lnav_blockset},
                        {"clear_block", lnav_clear_block},
                        {"clear_allblock", lnav_clear_allblock},
                        {"is_block", lnav_is_block},
                        {"find_path_by_grid", lnav_find_path_by_grid},
                        {"find_path", lnav_find_path},
                        {"find_line_obstacle", lnav_check_line_walkable},
                        {"get_connected_id", lnav_get_connected_id},
                        {"set_connected_id", lnav_set_connected_id},
                        {"get_max_connected_id", lnav_get_max_connected_id},
                        {"mark_connected", lnav_mark_connected},
                        {"dump_connected", lnav_dump_connected},
                        {"dump", lnav_dump},
                        {"quick_remark_area", lnav_quick_remark_area},
                        {NULL, NULL}};
        luaL_newlib(L, l);
        lua_setfield(L, -2, "__index");

        lua_pushcfunction(L, gc);
        lua_setfield(L, -2, "__gc");
    }
    return 1;
}

static int lnewmap(lua_State* L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 1);
    int width = getfield(L, "w");
    int height = getfield(L, "h");
    lua_assert(width > 0 && height > 0);
    int len = width * height;

    int map_men_len = (BITSLOT(len) + 1) * 2;

    Map* m = lua_newuserdata(L, sizeof(Map) + map_men_len * sizeof(m->m[0]));
    init_map(m, width, height, map_men_len);
    if (lua_getfield(L, 1, "obstacle") == LUA_TTABLE) {
        int i = 1;
        while (lua_geti(L, -1, i) == LUA_TTABLE) {
            lua_geti(L, -1, 1);
            int x = lua_tointeger(L, -1);
            lua_geti(L, -2, 2);
            int y = lua_tointeger(L, -1);
            setobstacle(L, m, x, y);
            lua_pop(L, 3);
            ++i;
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
    lmetatable(L);
    lua_setmetatable(L, -2);
    return 1;
}

LUAMOD_API int luaopen_navigation_c(lua_State* L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"new", lnewmap},
        {NULL, NULL},
    };
    luaL_newlib(L, l);
    return 1;
}