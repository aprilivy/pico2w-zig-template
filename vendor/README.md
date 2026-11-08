# vendor

`net` and `lwip` from the microzig 0.17.35 release, unchanged apart from their `build.zig.zon`:

- `lwip` lists `include` and `src` in `.paths`, and has `include/lwip.h` and `src/root.zig` from the microzig repo at tag 0.17.35. the released `lwip.tar.gz` leaves both out, so `net` can't build from it.
- `net` depends on `../lwip` instead of the release url.

once a microzig release ships a complete `lwip.tar.gz`, delete this folder and depend on that release's `net.tar.gz` instead.
