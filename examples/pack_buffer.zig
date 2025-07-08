const std = @import("std");
const ogg = @import("ogg");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var pb_write = ogg.PackBuffer{
        .c_packbuffer = undefined,
    };
    pb_write.writeInit();

    pb_write.write(0b101, 3); // 3 bits
    pb_write.write(0x1f, 5); // 5 bits
    std.debug.print("   Wrote 8 bits. Total bits: {d}, Total bytes: {d}\n", .{ pb_write.bits(), pb_write.bytes() });

    pb_write.writeAlign();
    std.debug.print("   Aligned. Total bits: {d}, Total bytes: {d}\n", .{ pb_write.bits(), pb_write.bytes() });
    std.debug.assert(pb_write.bits() == 8);
    std.debug.assert(pb_write.bytes() == 1);

    const more_data = "Zig is cool";
    pb_write.writeCopy(more_data);
    std.debug.print("   Wrote '{s}'. Total bits: {d}, Total bytes: {d}\n", .{ more_data, pb_write.bits(), pb_write.bytes() });

    const packed_data = pb_write.buffer();
    const packed_data_copy = try allocator.dupe(u8, packed_data);
    defer allocator.free(packed_data_copy);

    var pb_read = ogg.PackBuffer{ .c_packbuffer = undefined };
    pb_read.readInit(packed_data_copy);

    const look_val = try pb_read.look(3);
    std.debug.print("   Looked at 3 bits: {b}\n", .{look_val});
    std.debug.assert(look_val == 0b101);

    const read_val1 = try pb_read.read(3);
    std.debug.print("   Read 3 bits: {b}\n", .{read_val1});
    std.debug.assert(read_val1 == 0b101);
    std.debug.print("   Bits read so far: {d}\n", .{pb_read.bitsRead()});

    const read_val2 = try pb_read.read(5);
    std.debug.print("   Read 5 bits: {b}\n", .{read_val2});
    std.debug.assert(read_val2 == 0x1f);
    std.debug.print("   Bits read so far: {d}\n", .{pb_read.bitsRead()});

    pb_read.advance(@intCast(pb_write.bits() - pb_read.bitsRead() - @as(c_long, @intCast(more_data.len * 8))));
    std.debug.print("   Advanced past padding. Bits read so far: {d}\n", .{pb_read.bitsRead()});

    var read_back_buffer = std.ArrayList(u8).init(allocator);
    defer read_back_buffer.deinit();
    while (pb_read.bitsRead() < pb_write.bits()) {
        const byte = try pb_read.read(8);
        try read_back_buffer.append(@intCast(byte));
    }

    std.debug.print("   Read back string: '{s}'\n", .{read_back_buffer.items});

    std.debug.assert(std.mem.eql(u8, read_back_buffer.items, more_data));
}
