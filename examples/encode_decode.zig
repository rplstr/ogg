const std = @import("std");
const ogg = @import("ogg");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var stream_enc = ogg.StreamState.init(12345);
    defer stream_enc.deinit();

    const packet1_data = "Hello Ogg!";
    const packet2_data = "This is a test.";
    const packet3_data = "Another packet.";

    var packet1 = ogg.Packet{
        .bytes = packet1_data,
        .is_beginning_of_stream = true,
        .is_end_of_stream = false,
        .granule_pos = 0,
        .packet_num = 0,
    };
    var packet2 = ogg.Packet{
        .bytes = packet2_data,
        .is_beginning_of_stream = false,
        .is_end_of_stream = false,
        .granule_pos = 1000,
        .packet_num = 1,
    };
    var packet3 = ogg.Packet{
        .bytes = packet3_data,
        .is_beginning_of_stream = false,
        .is_end_of_stream = true,
        .granule_pos = 2000,
        .packet_num = 2,
    };

    try stream_enc.packetIn(&packet1);
    try stream_enc.packetIn(&packet2);
    try stream_enc.packetIn(&packet3);

    var ogg_data = std.ArrayList(u8).init(allocator);
    defer ogg_data.deinit();

    var page = ogg.Page{ .c_page = undefined };
    while (stream_enc.pageOut(&page)) {
        std.debug.print("   Got a page of size {d} (header) + {d} (body)\n", .{ page.header().len, page.body().len });
        try ogg_data.writer().writeAll(page.header());
        try ogg_data.writer().writeAll(page.body());
    }

    while (stream_enc.flush(&page)) {
        std.debug.print("   Got a flushed page of size {d} (header) + {d} (body)\n", .{ page.header().len, page.body().len });
        try ogg_data.writer().writeAll(page.header());
        try ogg_data.writer().writeAll(page.body());
    }

    std.debug.print("   Total encoded data size: {d} bytes\n", .{ogg_data.items.len});

    var sync = ogg.SyncState.init();
    defer sync.deinit();

    const buffer = sync.buffer(ogg_data.items.len);
    @memcpy(buffer, ogg_data.items);
    sync.wrote(ogg_data.items.len);

    var stream_dec = ogg.StreamState.init(12345);
    defer stream_dec.deinit();

    var decoded_packets = std.ArrayList([]const u8).init(allocator);
    defer decoded_packets.deinit();

    while (sync.pageOut(&page) == .success) {
        std.debug.print("   Decoded a page with serial {d} and {d} packets.\n", .{ page.serialNumber(), page.numPackets() });
        try stream_dec.pageIn(&page);

        var packet_out = ogg.Packet{};
        while (try stream_dec.packetOut(&packet_out)) {
            std.debug.print("     Decoded packet #{d} with size {d}\n", .{ packet_out.packet_num, packet_out.bytes.len });
            try decoded_packets.append(try allocator.dupe(u8, packet_out.bytes));
        }
    }

    std.debug.assert(decoded_packets.items.len == 3);
    std.debug.assert(std.mem.eql(u8, decoded_packets.items[0], packet1_data));
    std.debug.assert(std.mem.eql(u8, decoded_packets.items[1], packet2_data));
    std.debug.assert(std.mem.eql(u8, decoded_packets.items[2], packet3_data));
    for (decoded_packets.items) |p| allocator.free(p);
}
