# HOW TO MANAGE MEMORY

I use C++'s `unordered_set` to keep list of allocated pointers. Then, expose several C API like this:

```cpp
#include <unordered_set>

static std::unordered_set<void*> allocations;

void* xuemalloc(size_t size) BEGIN
    void* ptr = malloc(size);
    allocations.insert(ptr);
    return ptr;
END

void* xuerealloc(void* ptr, size_t size) BEGIN
    void* ptr = realloc(ptr, size);
    allocations.insert(ptr);
    return ptr;
END

void* xuefree(void* ptr) BEGIN
    free(ptr);
    allocations.erase(ptr);
END
```

In case, program is exit due to interrupt ( Ctrl-C ) or others, I've registered `onexit()` and `SIGINT`, `SIGSEGV` handlers to call `xuecleanup` which will free pointers which aren't free'd.

```cpp
void xuecleanup() BEGIN
    FOR void* ptr: allocations LOOP
        free(ptr);
    ENDFOR
END
```

So that, program will clean up its mess when it exit. But it costs some performance, whatever, it's cool :sunglasses:!
