# XueLand ( 雪 )

![LICENSE](https://img.shields.io/github/license/xueland/xue?color=green&label=LICENSE&style=flat-square)
![LANGUAGE](https://img.shields.io/static/v1?label=LANGUAGE&message=NIM&style=flat-square)

Just a language called XueLand. Imagine a Lua-inspired scripting language which supports multi-paradigms ( procedural, functional or OOP, etc. ) and can be compiled into IR executable for later use!

## HOW TO CALL

You can call whatever as u like: Xue, XueLand or 雪地.

```
雪 ( Snow - from CN ) + Land ( from EN ) = XueLand ( SnowLand )
```

## HOW TO BUILD

Just clone the repo, then run `nimble build` or `build script`.

```bash
$ git clone https://github.com/xueland/xue && cd xue
$ ./scripts/build.sh release
```

Tested and built on `Linux`. Should works on `macOS` and `Windows` too. `clang` is required. `gcc` is not working. I don't know. I'll investigate later!

## THANKS AND RESOURCES

Special thanks to:

- [@mrthetkhine](https://github.com/mrthetkhine): I've got a lot of inspiration from SAYA THET KHINE!
- [@munificent](https://github.com/munificent): for his awesome book called [CRAFTING INTERPRETERS](https://craftinginterpreters.com).
- [@davidcallanan](https://github.com/davidcallanan): for his awesome tutorial on [MAKING BASIC INTERPRETER](https://www.youtube.com/playlist?list=PLZQftyCk7_SdoVexSmwy_tBgs7P0b97yD).

Other Resources:

- [Write an Interpreter in Go](https://interpreterbook.com)
- [Write a Compiler in Go](https://compilerbook.com)
- [Simple Virtual Machine in C](https://felix.engineer/blogs/virtual-machine-in-c)
- [Pratt Parser in Go](https://quasilyte.dev/blog/post/pratt-parsers-go/)
- [Pratt Parser in Java](https://journal.stuffwithstuff.com/2011/03/19/pratt-parsers-expression-parsing-made-easy)
- [Wren Programming Language](https://wren.io)

XueLand won't exists, without them!

## LICENSE

XueLand compiler, virtual machine and standard libs are licensed under MIT License. For more details, see [LICENSE](LICENSE).
