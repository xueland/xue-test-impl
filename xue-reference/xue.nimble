version                     = "1.0.0"
author                      = "Hein Thant Maung Maung"
description                 = "Just a language called XueLand"
license                     = "MIT"
srcDir                      = "src"
bin                         = @["executable/xuec"]
namedBin["executable/xuec"] = "build/xuec"

requires "nim >= 1.4.8"
