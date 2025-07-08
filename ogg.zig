const std = @import("std");

pub const c = @cImport({
    @cInclude("ogg/ogg.h");
});

pub const Error = error{
    InternalError,
    PacketInFailed,
    PacketOutHole,
    PageInFailed,
    ReadPastEnd,
};

/// Represents a single data packet.
pub const Packet = struct {
    /// The raw bytes of the packet. The lifetime of this slice must be managed by the caller
    /// when creating a packet to be encoded. When receiving a packet from decoding,
    /// its lifetime is tied to the `StreamState` it came from.
    bytes: []const u8 = &.{},
    /// True if this is the first packet of a logical bitstream (b_o_s).
    is_beginning_of_stream: bool = false,
    /// True if this is the last packet of a logical bitstream (e_o_s).
    is_end_of_stream: bool = false,
    /// The granule position of this packet. This is an abstract position marker,
    /// its meaning is defined by the codec.
    granule_pos: i64 = -1,
    /// A sequence number for this packet.
    packet_num: i64 = -1,

    c_packet: c.ogg_packet = .{},
};

/// Represents a page, a fundamental unit of data in an Ogg bitstream.
pub const Page = struct {
    c_page: c.ogg_page,

    /// Returns the raw header of the Ogg page.
    pub fn header(self: Page) []const u8 {
        return self.c_page.header[0..@intCast(self.c_page.header_len)];
    }

    /// Returns the raw body (payload) of the Ogg page.
    pub fn body(self: Page) []const u8 {
        return self.c_page.body[0..@intCast(self.c_page.body_len)];
    }

    /// Returns the serial number of the logical bitstream this page belongs to.
    pub fn serialNumber(self: Page) c_int {
        return c.ogg_page_serialno(&self.c_page);
    }

    /// Returns the page number within the logical bitstream.
    pub fn pageNumber(self: Page) c_long {
        return c.ogg_page_pageno(&self.c_page);
    }

    /// Returns true if this page is at the beginning of the logical stream.
    pub fn isBeginningOfStream(self: Page) bool {
        return c.ogg_page_bos(&self.c_page) != 0;
    }

    /// Returns true if this page is at the end of the logical stream.
    pub fn isEndOfStream(self: Page) bool {
        return c.ogg_page_eos(&self.c_page) != 0;
    }

    /// Returns the granule position of the page.
    pub fn granulePos(self: Page) i64 {
        return c.ogg_page_granulepos(&self.c_page);
    }

    /// Returns the number of packets that complete on this page.
    pub fn numPackets(self: Page) c_int {
        return c.ogg_page_packets(&self.c_page);
    }
};

/// Manages the state of a single logical Ogg bitstream for encoding or decoding.
pub const StreamState = struct {
    c_stream: c.ogg_stream_state,

    /// Initializes a new stream state for a logical bitstream.
    /// `serial_no` is a unique number identifying this logical stream.
    pub fn init(serial_no: c_int) StreamState {
        var self: StreamState = undefined;
        const ret = c.ogg_stream_init(&self.c_stream, serial_no);
        std.debug.assert(ret == 0);
        return self;
    }

    /// Releases all resources associated with the stream state.
    pub fn deinit(self: *StreamState) void {
        _ = c.ogg_stream_clear(&self.c_stream);
    }

    /// Resets the stream state to its initial state.
    pub fn reset(self: *StreamState) void {
        const ret = c.ogg_stream_reset(&self.c_stream);
        std.debug.assert(ret == 0);
    }

    /// Submits a packet to the stream for encoding.
    pub fn packetIn(self: *StreamState, packet: *Packet) Error!void {
        packet.c_packet.packet = @constCast(packet.bytes.ptr);
        packet.c_packet.bytes = @intCast(packet.bytes.len);
        packet.c_packet.b_o_s = @intFromBool(packet.is_beginning_of_stream);
        packet.c_packet.e_o_s = @intFromBool(packet.is_end_of_stream);
        packet.c_packet.granulepos = packet.granule_pos;
        packet.c_packet.packetno = packet.packet_num;

        if (c.ogg_stream_packetin(&self.c_stream, &packet.c_packet) != 0) {
            return Error.PacketInFailed;
        }
    }

    /// Retrieves a packet from the stream during decoding.
    /// Returns `true` if a packet was retrieved, `false` if more data is needed.
    pub fn packetOut(self: *StreamState, packet: *Packet) Error!bool {
        const ret = c.ogg_stream_packetout(&self.c_stream, &packet.c_packet);
        if (ret < 0) return Error.PacketOutHole;
        if (ret == 0) return false;

        packet.bytes = packet.c_packet.packet[0..@intCast(packet.c_packet.bytes)];
        packet.is_beginning_of_stream = packet.c_packet.b_o_s != 0;
        packet.is_end_of_stream = packet.c_packet.e_o_s != 0;
        packet.granule_pos = packet.c_packet.granulepos;
        packet.packet_num = packet.c_packet.packetno;
        return true;
    }

    /// Retrieves a page of Ogg data from the stream during encoding.
    /// This should be called after submitting packets with `packetIn`.
    /// Returns `true` if a page was retrieved, `false` if no full page is ready.
    pub fn pageOut(self: *StreamState, page: *Page) bool {
        const ret = c.ogg_stream_pageout(&self.c_stream, &page.c_page);
        if (ret == 0) return false;
        return true;
    }

    /// Submits a page to the stream for decoding.
    pub fn pageIn(self: *StreamState, page: *Page) Error!void {
        if (c.ogg_stream_pagein(&self.c_stream, &page.c_page) != 0) {
            return Error.PageInFailed;
        }
    }

    /// Forces the remaining packet data to be flushed into a final page.
    /// This is used at the end of encoding.
    /// Returns `true` if a page was retrieved, `false` if there are no more pages.
    pub fn flush(self: *StreamState, page: *Page) bool {
        const ret = c.ogg_stream_flush(&self.c_stream, &page.c_page);
        if (ret == 0) return false;
        return true;
    }
};

/// Manages synchronization and page extraction from a raw Ogg bytestream.
pub const SyncState = struct {
    c_sync: c.ogg_sync_state,

    pub const PageOutResult = enum {
        success,
        needs_more_data,
        hole_in_data,
    };

    /// Initializes a new synchronization state.
    pub fn init() SyncState {
        var self: SyncState = undefined;
        const ret = c.ogg_sync_init(&self.c_sync);
        std.debug.assert(ret == 0);
        return self;
    }

    /// Releases all resources associated with the synchronization state.
    pub fn deinit(self: *SyncState) void {
        _ = c.ogg_sync_clear(&self.c_sync);
    }

    /// Resets the synchronization state.
    pub fn reset(self: *SyncState) void {
        const ret = c.ogg_sync_reset(&self.c_sync);
        std.debug.assert(ret == 0);
    }

    /// Gets a buffer from the sync state to write new data into.
    /// `size` is the number of bytes you want to write.
    /// The returned slice's lifetime is managed by the `SyncState`.
    pub fn buffer(self: *SyncState, size: usize) []u8 {
        return c.ogg_sync_buffer(&self.c_sync, @intCast(size))[0..size];
    }

    /// Informs the sync state how many bytes were written into the buffer
    /// obtained from `buffer()`.
    pub fn wrote(self: *SyncState, bytes_written: usize) void {
        const ret = c.ogg_sync_wrote(&self.c_sync, @intCast(bytes_written));
        std.debug.assert(ret == 0);
    }

    /// Attempts to extract a page from the data provided to the sync state.
    pub fn pageOut(self: *SyncState, page: *Page) PageOutResult {
        const ret = c.ogg_sync_pageout(&self.c_sync, &page.c_page);
        if (ret > 0) return .success;
        if (ret == 0) return .needs_more_data;
        return .hole_in_data;
    }
};

/// Provides bit-level packing and unpacking capabilities.
pub const PackBuffer = struct {
    c_packbuffer: c.oggpack_buffer,

    /// Initializes the buffer for writing.
    pub fn writeInit(self: *PackBuffer) void {
        c.oggpack_writeinit(&self.c_packbuffer);
    }

    /// Writes a specified number of bits from a value into the buffer.
    /// `value` is the data to write, `bit` is the number of bits (1 to 32).
    pub fn write(self: *PackBuffer, value: u32, bit: c_int) void {
        c.oggpack_write(&self.c_packbuffer, value, bit);
    }

    /// Copies a block of bytes into the buffer.
    pub fn writeCopy(self: *PackBuffer, source: []const u8) void {
        c.oggpack_writecopy(&self.c_packbuffer, @constCast(source.ptr), @as(c_long, @intCast(source.len)) * 8);
    }

    /// Resets the buffer to an empty state.
    pub fn deinit(self: *PackBuffer) void {
        c.oggpack_writeclear(&self.c_packbuffer);
    }

    /// Truncates the buffer to a specific number of bits.
    pub fn writeTruncate(self: *PackBuffer, bit: i32) void {
        c.oggpack_writetrunc(&self.c_packbuffer, bit);
    }

    /// Zero-pads the buffer to the next byte boundary.
    pub fn writeAlign(self: *PackBuffer) void {
        c.oggpack_writealign(&self.c_packbuffer);
    }

    /// Returns the number of bytes currently in the buffer.
    pub fn bytes(self: *const PackBuffer) c_long {
        return c.oggpack_bytes(@constCast(&self.c_packbuffer));
    }

    /// Returns the number of bits currently in the buffer.
    pub fn bits(self: *const PackBuffer) c_long {
        return c.oggpack_bits(@constCast(&self.c_packbuffer));
    }

    /// Returns the internal buffer data.
    pub fn buffer(self: *const PackBuffer) []const u8 {
        return c.oggpack_get_buffer(@constCast(&self.c_packbuffer))[0..@as(usize, @intCast(self.bytes()))];
    }

    /// Initializes the buffer for reading from a source slice.
    pub fn readInit(self: *PackBuffer, source: []const u8) void {
        c.oggpack_readinit(&self.c_packbuffer, @constCast(source.ptr), @intCast(source.len));
    }

    /// Reads a specified number of bits from the buffer.
    /// Returns the value read, or -1 on error (e.g., reading past end of buffer).
    pub fn read(self: *PackBuffer, bit: c_int) Error!c_long {
        const ret = c.oggpack_read(&self.c_packbuffer, bit);
        if (ret == -1) return Error.ReadPastEnd;
        return ret;
    }

    /// Reads one bit from the buffer.
    pub fn read1(self: *PackBuffer) Error!c_long {
        const ret = c.oggpack_read1(&self.c_packbuffer);
        if (ret == -1) return Error.ReadPastEnd;
        return ret;
    }

    /// Peeks at the next `bits` number of bits without advancing the read pointer.
    pub fn look(self: *const PackBuffer, bit: c_int) Error!c_long {
        const ret = c.oggpack_look(@constCast(&self.c_packbuffer), bit);
        if (ret == -1) return Error.ReadPastEnd;
        return ret;
    }

    /// Peeks at the next bit.
    pub fn look1(self: *const PackBuffer) Error!c_long {
        const ret = c.oggpack_look1(@constCast(&self.c_packbuffer));
        if (ret == -1) return Error.ReadPastEnd;
        return ret;
    }

    /// Advances the read pointer by `bit`.
    pub fn advance(self: *PackBuffer, bit: c_int) void {
        c.oggpack_adv(&self.c_packbuffer, bit);
    }

    /// Advances the read pointer by one bit.
    pub fn advance1(self: *PackBuffer) void {
        c.oggpack_adv1(&self.c_packbuffer);
    }

    /// Returns the number of bits read so far.
    pub fn bitsRead(self: *const PackBuffer) c_long {
        const ptr_addr = @intFromPtr(self.c_packbuffer.ptr);
        const buffer_addr = @intFromPtr(self.c_packbuffer.buffer);
        const byte_offset = ptr_addr - buffer_addr;
        return @as(c_long, @intCast(byte_offset)) * 8 + self.c_packbuffer.endbit;
    }
};
