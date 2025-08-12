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
    {4, 8},
    {4, 9},
})

nav.core:dump()
nav.core:dump_connected()

nav:merge_area({x = 0, y = 8}, {x = 9, y = 9})

nav.core:dump()
nav.core:dump_connected()