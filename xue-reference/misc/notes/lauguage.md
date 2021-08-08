# XueLand ( 雪 ) DESIGN NOTES

Just a note for various ideas which appeared while implementing XueLand.

## Scopes

In XueLand, global variables use static dispatch. I mean global variable must be declared before accessing.

```
proc bar() begin
    echo baz; <- this will throw error at compile time
endproc

let baz = "FOO";
```

This code might works on other languages, but XueLand won't allow this.

## Comments

XueLand supports various comments form!

```
# this is a comment. These kind of comment goes to the end of Line
-- this is a comment too.
<- this is also a comment too.

---
this is a multiple line comment.
oops! I'm at the new line.
---

// this is a comment too.
/* this is a multi-line comment too. But it's classical :P */
```

## Notes On Xue's String

XueLand strings are similar to strings from PHP. XueLand won't escape and string interpolation won't work in single-quoted strings.

```
let name = "Hein Thant";
let languageName = "雪";

echo "%(name) created %(languageName).\nIt has cool features.";

---
above code will output:
    Hein Thant created 雪.
    It has cool features.
---

echo '%(name) created %(languageName).\nIt has cool features.';

---
above code will output:
    %(name) created %(languageName).\nIt has cool features.
---
```

For example, when dealing with **windows' path**, single-quoted strings are useful!

```
let AppDataFolderPath = 'C:\Users\heinthanth\AppData';

echo "XueLand configurations are located at %(AppDataFolderPath)\\Local\\HIIIiN\\XueLand."

---
above code will output:
    XueLand configurations are located at C:\Users\heinthanth\AppData\Local\HIIIiN\XueLand.
---
```

XueLand string supports following escape sequences:

```
\0                      :=  null character
\a                      :=  alert
\b                      :=  backspace
\e                      :=  escape character
\f                      :=  form feed
\n                      :=  line feed
\r                      :=  carriage return
\t                      :=  tabulator
\v                      :=  vertical tabulator
\\                      :=  backslash
\'                      :=  single quote
\"                      :=  double quote
\%                      :=  string interpolation
```

But, in single-quoted string, `\"` won't work although it should works. It's also for `\'` in double-quote, etc.
