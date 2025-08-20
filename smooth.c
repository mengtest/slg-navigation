
#include "smooth.h"
#include "map.h"
#include <math.h>

// 检查线段是否与格子相交
int line_intersects_grid(float x1, float y1, float x2, float y2, int gx, int gy) {
    // 格子边界
    float left = gx, right = gx + 1;
    float bottom = gy, top = gy + 1;
    
    // 线段参数方程: P = (x1,y1) + t*((x2,y2)-(x1,y1))，t在[0,1]
    float dx = x2 - x1;
    float dy = y2 - y1;
    
    // 检查与格子四条边的交集
    float t_min = 0, t_max = 1;
    
    // 检查垂直边界 (left, right)
    if (dx != 0) {
        float t1 = (left - x1) / dx;
        float t2 = (right - x1) / dx;
        if (t1 > t2) { float temp = t1; t1 = t2; t2 = temp; }
        t_min = fmaxf(t_min, t1);
        t_max = fminf(t_max, t2);
    } else if (x1 < left || x1 > right) {
        return 0; // 线段与格子不相交
    }
    
    // 检查水平边界 (bottom, top)  
    if (dy != 0) {
        float t1 = (bottom - y1) / dy;
        float t2 = (top - y1) / dy;
        if (t1 > t2) { float temp = t1; t1 = t2; t2 = temp; }
        t_min = fmaxf(t_min, t1);
        t_max = fminf(t_max, t2);
    } else if (y1 < bottom || y1 > top) {
        return 0; // 线段与格子不相交
    }
    
    return t_min <= t_max;
}

int find_line_obstacle(Map* m, float x1, float y1, float x2, float y2) {
    // 确定需要检查的格子范围
    int min_x = (int)fminf(x1, x2);
    int max_x = (int)fmaxf(x1, x2);
    int min_y = (int)fminf(y1, y2);
    int max_y = (int)fmaxf(y1, y2);
    
    // 检查线段经过的每个格子
    for (int y = min_y; y <= max_y; y++) {
        for (int x = min_x; x <= max_x; x++) {
            if (x >= 0 && x < m->width && y >= 0 && y < m->height) {
                int pos = xy2pos(m, x, y);
                if (!map_walkable(m, pos)) {
                    // 检查线段是否与这个障碍物格子相交
                    if (line_intersects_grid(x1, y1, x2, y2, x, y)) {
                        return pos;
                    }
                }
            }
        }
    }
    
    return -1;
}

void smooth_path(Map* m, int smooth_count) {
    // 如果平滑数量小于3，不进行平滑处理
    if (smooth_count < 3) {
        return;
    }
    
    int x1, y1, x2, y2;
    // 确定要处理的路点范围：前smooth_count个路点（索引从后往前数）
    int start_idx = (smooth_count >= m->ipath_len) ? 0 : m->ipath_len - smooth_count;
    
    for (int i = m->ipath_len - 1; i >= start_idx + 2; i--) {
        for (int j = start_idx; j <= i - 2; j++) {
            pos2xy(m, m->ipath[i], &x1, &y1);
            pos2xy(m, m->ipath[j], &x2, &y2);
            // 使用浮点坐标（格子中心）进行障碍物检测
            if (find_line_obstacle(m, x1 + 0.5, y1 + 0.5, x2 + 0.5, y2 + 0.5) < 0) {
                int offset = i - j - 1;
                for (int k = j + 1; k <= m->ipath_len - 1 - offset; k++) {
                    m->ipath[k] = m->ipath[k + offset];
                }
                m->ipath_len -= offset;
                i = i - offset;
                break;
            }
        }
    }
}
