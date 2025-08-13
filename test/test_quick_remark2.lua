local navigation = require "navigation"
local w = 20
local h = 10
local nav = navigation.new(w, h, {
})

nav.core:dump()
nav.core:dump_connected()


nav:quick_remark_area(4, 8, 4, 8, true)

nav.core:dump()
nav.core:dump_connected()

nav:quick_remark_area(4, 8, 4, 8, false)

nav.core:dump()
nav.core:dump_connected()
