# Package

version                         = "1.0.0"
author                          = "Hein Thant Maung Maung"
description                     = "Just a language called XueLand"
license                         = "MIT"

backend                         = "c"
bin                             = @["src/executable/xue", "src/executable/xuec"]
namedBin["src/executable/xue"]  = "build/xue"
namedBin["src/executable/xuec"] = "build/xuec"

# Dependencies

requires "nim >= 1.4.6"
