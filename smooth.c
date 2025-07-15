
#include "smooth.h"
#include "map.h"
#include <math.h>

int find_line_obstacle(Map* m, float x1, float y1, float x2, float y2) {
    // 检查起点和终点
    int start_x = (int)x1;
    int start_y = (int)y1;
    int end_x = (int)x2;
    int end_y = (int)y2;
    
    if (!map_walkable(m, xy2pos(m, start_x, start_y))) {
        return xy2pos(m, start_x, start_y);
    }
    if (!map_walkable(m, xy2pos(m, end_x, end_y))) {
        return xy2pos(m, end_x, end_y);
    }
    
    // 使用 Bresenham 算法遍历直线上的所有格子
    int dx = abs(end_x - start_x);
    int dy = abs(end_y - start_y);
    int x = start_x;
    int y = start_y;
    
    int x_inc = (end_x > start_x) ? 1 : -1;
    int y_inc = (end_y > start_y) ? 1 : -1;
    
    int error = dx - dy;
    
    // 遍历路径上的每个格子
    while (x != end_x || y != end_y) {
        // 移动到下一个格子
        int error2 = 2 * error;
        
        if (error2 > -dy) {
            error -= dy;
            x += x_inc;
            // 每次移动后立即检查
            if (!map_walkable(m, xy2pos(m, x, y))) {
                return xy2pos(m, x, y);
            }
        }
        
        if (error2 < dx) {
            error += dx;
            y += y_inc;
            // 每次移动后立即检查
            if (!map_walkable(m, xy2pos(m, x, y))) {
                return xy2pos(m, x, y);
            }
        }
    }
    
    return -1;
}

void smooth_path(Map* m) {
    int x1, y1, x2, y2;
    for (int i = m->ipath_len - 1; i >= 0; i--) {
        for (int j = 0; j < i - 1; j++) {
            pos2xy(m, m->ipath[i], &x1, &y1);
            pos2xy(m, m->ipath[j], &x2, &y2);
            // printf("check (%d)%d <=> (%d)%d\n", i, m->ipath[i], j, m->ipath[j]);
            if (find_line_obstacle(m, x1 + 0.5, y1 + 0.5, x2 + 0.5,
                                    y2 + 0.5) < 0) {
                int offset = i - j - 1;
                // printf("merge (%d) to (%d) offset:%d\n", i, j, offset);
                for (int k = j + 1; k <= m->ipath_len - 1 - offset; k++) {
                    m->ipath[k] = m->ipath[k + offset];
                    // printf("%d <= %d\n", k, k + offset);
                }
                m->ipath_len -= offset;
                i = j + 1;
                break;
            }
        }
    }
}
