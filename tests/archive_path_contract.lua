local api = dofile(arg[1])
local isSafe = api._internals.archivePathIsSafe

assert(isSafe("Scripts/main.lua"))
assert(isSafe("Songs/6037/info.dat"))
assert(not isSafe("../outside.txt"))
assert(not isSafe("Songs/6037/../../outside.txt"))
assert(not isSafe("/absolute/outside.txt"))
assert(not isSafe("C:/absolute/outside.txt"))
assert(not isSafe("Songs\\6037\\..\\outside.txt"))

print("archive path contract ok")
