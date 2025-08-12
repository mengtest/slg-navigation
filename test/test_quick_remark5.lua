local navigation = require "navigation"
local w = 20
local h = 10
local nav = navigation.new(w, h, {
    {4, 0},
    {4, 1},
    {4, 2},
    {4, 3},
    {4, 4},
    {4, 5},
    {4, 6},
    {4, 7},
})

nav.core:dump()
nav.core:dump_connected()


nav:quick_remark_area2(4, 4, 8, 9, true)

nav.core:dump()
nav.core:dump_connected()

nav:quick_remark_area2(4, 4, 8, 9, false)

nav.core:dump()
nav.core:dump_connected()
