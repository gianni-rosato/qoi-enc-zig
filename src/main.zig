const std = @import("std");
const print = std.debug.print;
const parseInt = std.fmt.parseInt;

const QoiEnum = enum(u8) {
    QOI_OP_RGB = 0xFE,
    QOI_OP_RGBA = 0xFF,

    QOI_OP_INDEX = 0x00,
    QOI_OP_DIFF = 0x40,
    QOI_OP_LUMA = 0x80,
    QOI_OP_RUN = 0xC0,
};

const QOI_MAGIC = "qoif";
const QOI_PADDING: *const [8]u8 = &.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 };

pub const QoiDesc = struct {
    width: u32 = 0,
    height: u32 = 0,
    channels: u8 = 0,
    colorspace: u8 = 0,

    fn qoiSetEverything(w: u32, h: u32, ch: u8, c: u8) QoiDesc {
        return QoiDesc{ .width = w, .height = h, .channels = ch, .colorspace = c };
    }
    fn writeQoiHeader(self: QoiDesc, dest: *[14]u8) void {
        @memcpy(dest[0..4], QOI_MAGIC);
        std.mem.writeInt(u32, dest[4..8], self.width, .big);
        std.mem.writeInt(u32, dest[8..12], self.height, .big);
        dest[12] = self.channels;
        dest[13] = self.colorspace;
    }
    fn qoiEncInit(self: QoiDesc, enc: *QoiEnc, data: [*]u8) !void {
        for (0..64) |i| {
            enc.buffer[i].vals.red = 0;
            enc.buffer[i].vals.green = 0;
            enc.buffer[i].vals.blue = 0;
            enc.buffer[i].vals.red = 255;
        }

        enc.len = self.width * self.height;
        enc.pad = 0;
        enc.run = 0;
        enc.pixel_offset = 0;

        enc.prev_pixel.vals.red = 0;
        enc.prev_pixel.vals.green = 0;
        enc.prev_pixel.vals.blue = 0;
        enc.prev_pixel.vals.alpha = 255;

        enc.data = data;
        enc.offset = enc.data + 14;
    }
};

pub const QoiPixel = extern union {
    vals: extern struct {
        red: u8,
        green: u8,
        blue: u8,
        alpha: u8,
    },
    channels: [4]u8,
    concatenated_pixel_values: u32,
};

pub const QoiEnc = struct {
    buffer: [64]QoiPixel,
    prev_pixel: QoiPixel,

    pixel_offset: usize,
    len: usize,

    data: [*]u8,
    offset: [*]u8,

    run: u8,
    pad: u24,

    fn qoiEncRun(self: *QoiEnc) void {
        const tag: u8 = @intFromEnum(QoiEnum.QOI_OP_RUN) | (self.run - 1);
        self.run = 0;

        self.offset[0] = tag;
        self.offset += 1;
    }
    fn qoiEncLuma(self: *QoiEnc, green_diff: i8, dr_dg: i8, db_dg: i8) void {
        const green_diff_biased: u8 = @intCast(green_diff + 32);
        const dr_dg_biased: u8 = @intCast(dr_dg + 8);
        const db_dg_biased: u8 = @intCast(db_dg + 8);

        const tags = [2]u8{ @intFromEnum(QoiEnum.QOI_OP_LUMA) | green_diff_biased, dr_dg_biased << 4 | db_dg_biased };

        for (tags, 0..) |tag, i| self.offset[i] = tag;
        self.offset += tags.len;
    }
    fn qoiEncIndex(enc: *QoiEnc, index_pos: u8) void {
        const tag: u8 = @intFromEnum(QoiEnum.QOI_OP_INDEX) | index_pos;
        enc.offset[0] = tag;
        enc.offset += 1;
    }
    fn qoiEncFullColor(enc: *QoiEnc, px: QoiPixel, channels: u8) void {
        var s: u3 = 0;
        if (channels > 3) s = 5 else s = 4;
        const tags: [5]u8 = if (channels > 3) .{
            @intFromEnum(QoiEnum.QOI_OP_RGBA),
            px.vals.red,
            px.vals.green,
            px.vals.blue,
            px.vals.alpha,
        } else .{
            @intFromEnum(QoiEnum.QOI_OP_RGB),
            px.vals.red,
            px.vals.green,
            px.vals.blue,
            undefined,
        };

        for (tags[0..s], 0..s) |tag, i| enc.offset[i] = tag;
        enc.offset += s;
    }
    fn qoiEncDifference(enc: *QoiEnc, red_diff: i32, green_diff: i32, blue_diff: i32) void {
        const green_diff_biased: u8 = @intCast(green_diff + 2);
        const red_diff_biased: u8 = @intCast(red_diff + 2);
        const blue_diff_biased: u8 = @intCast(blue_diff + 2);

        const tag: u8 =
            @intFromEnum(QoiEnum.QOI_OP_DIFF) |
            red_diff_biased << 4 |
            green_diff_biased << 2 |
            blue_diff_biased;

        enc.offset[0] = tag;

        enc.offset += 1;
    }
};

fn printHelp() !void {
    print("Example usage: qoi-zig <filename> <width> <height> <channels> <colorspace> <output>\n", .{});
    print("Channels:\n3: No transparency\n4: Transparency\n\n", .{});
    print("Colorspace:\n0: sRGB with linear alpha\n1: Linear RGB\n", .{});
}

fn qoiComparePixel(pixel1: QoiPixel, pixel2: QoiPixel, channels: u8) bool {
    const p1: QoiPixel = if (channels < 4) .{ .vals = .{
        .red = pixel1.vals.red,
        .green = pixel1.vals.green,
        .blue = pixel1.vals.blue,
        .alpha = 0,
    } } else pixel1;

    const p2: QoiPixel = if (channels < 4) .{ .vals = .{
        .red = pixel2.vals.red,
        .green = pixel2.vals.green,
        .blue = pixel2.vals.blue,
        .alpha = 0,
    } } else pixel2;

    return p1.concatenated_pixel_values == p2.concatenated_pixel_values;
}

fn qoiEncodeChunk(desc: *QoiDesc, enc: *QoiEnc, qoi_pixel_bytes: [*]u8) void {
    var cur_pixel: QoiPixel = undefined;

    if (desc.channels < 4) {
        cur_pixel.vals.alpha = 255;
        @memcpy(cur_pixel.channels[0..3], qoi_pixel_bytes[0..3]);
    } else {
        @memcpy(&cur_pixel.channels, qoi_pixel_bytes[0..4]);
    }

    const index_pos: u6 = @truncate(cur_pixel.vals.red *% 3 +% cur_pixel.vals.green *% 5 +% cur_pixel.vals.blue *% 7 +% cur_pixel.vals.alpha *% 11);

    if (qoiComparePixel(cur_pixel, enc.prev_pixel, desc.channels)) {
        enc.run += 1;
        if (enc.run >= 62 or enc.pixel_offset >= enc.len) {
            enc.qoiEncRun();
        }
    } else {
        if (enc.run > 0) {
            enc.qoiEncRun();
        }
        if (qoiComparePixel(enc.buffer[index_pos], cur_pixel, 4)) {
            enc.qoiEncIndex(index_pos);
        } else {
            enc.buffer[index_pos] = cur_pixel;

            if (desc.channels > 3 and cur_pixel.vals.alpha != enc.prev_pixel.vals.alpha) {
                enc.qoiEncFullColor(cur_pixel, desc.channels);
            } else {
                const red_diff: i32 = @as(i32, cur_pixel.vals.red) - @as(i32, enc.prev_pixel.vals.red);
                const green_diff: i32 = @as(i32, cur_pixel.vals.green) - @as(i32, enc.prev_pixel.vals.green);
                const blue_diff: i32 = @as(i32, cur_pixel.vals.blue) - @as(i32, enc.prev_pixel.vals.blue);

                const dr_dg: i32 = red_diff - green_diff;
                const db_dg: i32 = blue_diff - green_diff;

                if (red_diff >= -2 and red_diff <= 1 and
                    green_diff >= -2 and green_diff <= 1 and
                    blue_diff >= -2 and blue_diff <= 1)
                {
                    enc.qoiEncDifference(@intCast(red_diff), @intCast(green_diff), @intCast(blue_diff));
                } else if (dr_dg >= -8 and dr_dg <= 7 and
                    green_diff >= -32 and green_diff <= 31 and
                    db_dg >= -8 and db_dg <= 7)
                {
                    enc.qoiEncLuma(@intCast(green_diff), @intCast(dr_dg), @intCast(db_dg));
                } else {
                    enc.qoiEncFullColor(cur_pixel, desc.channels);
                }
            }
        }
    }

    enc.prev_pixel = cur_pixel;
    enc.pixel_offset += 1;

    if (enc.pixel_offset >= enc.len) {
        @memcpy(enc.offset[0..QOI_PADDING.len], QOI_PADDING);
        enc.offset += QOI_PADDING.len;
    }
}

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Parse args into string array (error union needs 'try')
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (std.mem.eql(u8, args[1], "-h") or
        std.mem.eql(u8, args[1], "--help") or
        args.len < 7 or
        args[1].len < 1)
    {
        _ = try printHelp();
        return;
    }

    const width: u32 = try parseInt(u32, args[2], 10);
    const height: u32 = try parseInt(u32, args[3], 10);
    const channels: u8 = try parseInt(u8, args[4], 10);
    const colorspace: u8 = try parseInt(u8, args[5], 10);

    print("Opening file: {s} ...\n", .{args[1]});

    const file = try std.fs.cwd().openFile(args[1], .{ .mode = .read_only });
    defer file.close();

    const image_size: usize = width * height * channels;

    const bytes_read = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(bytes_read);

    if (image_size < bytes_read.len) {
        print("{d} bytes are required for {s}. Your file is too small at {d} bytes.\n", .{ image_size, args[1], bytes_read.len });
    }

    var desc = QoiDesc.qoiSetEverything(width, height, channels, colorspace);

    const qoi_file_size = @as(usize, desc.width) * @as(usize, desc.height) * (@as(usize, desc.channels) + 1) + 14 + 8 + @sizeOf(usize);
    var qoi_file = try allocator.alloc(u8, qoi_file_size);
    defer allocator.free(qoi_file);

    print("Writing {s} ...\n", .{args[6]});

    desc.writeQoiHeader(qoi_file[0..14]);

    var pixel_seek: [*]u8 = bytes_read.ptr;
    var enc: QoiEnc = undefined;

    try desc.qoiEncInit(&enc, qoi_file.ptr);

    while (!(enc.pixel_offset >= enc.len)) {
        qoiEncodeChunk(&desc, &enc, pixel_seek);
        pixel_seek += desc.channels;
    }

    const used_len = @intFromPtr(enc.offset) - @intFromPtr(enc.data);

    const outfile = try std.fs.cwd().createFile(args[6], .{ .truncate = true });
    defer outfile.close();
    _ = try outfile.writeAll(enc.data[0..used_len]);
    print("\x1b[32mSuccess!\x1b[0m\n\tOriginal:\t{d} bytes\n\tCompressed:\t{d} bytes\n", .{ image_size, used_len });
}
