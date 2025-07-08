<div align="center">

# ogg

Ogg is a multimedia container format, and the native file and stream format for the Xiph.org multimedia codecs. 

</div>

[Zig](https://ziglang.org) wrapper for the [Xiph.Org `libogg`](https://www.xiph.org/ogg/) library.

You can still access the raw C headers if you need functionality not exposed by the wrapper. For example:

```zig
const std = @import("std");
const ogg = @import("ogg");

pub fn main() void {
    var stream_state: ogg.c.ogg_stream_state = undefined;
    const ret = ogg.c.ogg_stream_init(&stream_state, 12345);
    std.debug.assert(ret == 0);
    _ = ogg.c.ogg_stream_clear(&stream_state);
}
```

### Adding to your project

1.  Add this repository as a dependency in your `build.zig.zon`. You can use `zig fetch`:
    ```sh
    zig fetch --save git+https://github.com/rplstr/ogg
    ```

2.  In your `build.zig`, add the dependency and link against it:
    ```zig
    const ogg = b.dependency("ogg", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("ogg", ogg.module("ogg"));
    exe.linkLibrary(ogg_dep.artifact("ogg"));
    ```

## Examples

You can find example usage in the `examples/` directory. To run them:

```sh
zig build run
```
