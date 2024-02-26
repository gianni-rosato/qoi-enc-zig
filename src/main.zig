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

// const QOI_OP_RGB: u8 = 0xFE;
// const QOI_OP_RGBA: u8 = 0xFF;

// const QOI_OP_INDEX: u8 = 0x00;
// const QOI_OP_DIFF: u8 = 0x40;
// const QOI_OP_LUMA: u8 = 0x80;
// const QOI_OP_RUN: u8 = 0xC0;

const QOI_MAGIC = "qoif";
const QOI_PADDING: [8]u8 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 };

pub const QoiDesc = struct {
    width: u32 = 0,
    height: u32 = 0,
    channels: u8 = 0,
    colorspace: u8 = 0,
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

comptime {
    if (@sizeOf(QoiPixel) != @sizeOf(u8) * 4) @compileError("oh no! padding! how");
}

pub const QoiEnc = struct {
    buffer: [64]QoiPixel,
    prev_pixel: QoiPixel,

    pixel_offset: usize,
    len: usize,

    data: [*]u8, // do these need to be multi pointers?
    offset: [*]u8,

    run: u8,
    pad: u24,
};

fn printHelp() !void {
    print("Example usage: qoi_enc <filename> <width> <height> <channels> <colorspace> <output>\n", .{});
    print("Channels:\n3: No transparency\n4: Transparency\n\n", .{});
    print("Colorspace:\n0: sRGB with linear alpha\n1: Linear RGB\n", .{});
}

fn qoiSetDimensions(desc: *QoiDesc, width: u32, height: u32) void {
    desc.width = width;
    desc.height = height;
}

fn qoiSetChannels(desc: *QoiDesc, channels: u8) void {
    desc.channels = channels;
}

fn qoiSetColorspace(desc: *QoiDesc, colorspace: u8) void {
    desc.colorspace = colorspace;
}

fn writeQoiHeader(desc: *QoiDesc, dest: *[14]u8) void {
    @memcpy(dest[0..4], QOI_MAGIC);
    std.mem.writeInt(u32, dest[4..8], desc.width, .big);
    std.mem.writeInt(u32, dest[8..12], desc.height, .big);
    dest[12] = desc.channels;
    dest[13] = desc.colorspace;
}

pub fn qoiSetPixelRGBA(pixel: *QoiPixel, red: u8, green: u8, blue: u8, alpha: u8) void {
    pixel.vals.red = red;
    pixel.vals.green = green;
    pixel.vals.blue = blue;
    pixel.vals.alpha = alpha;
}

pub fn qoiInitializePixel(pixel: *QoiPixel) void {
    qoiSetPixelRGBA(pixel, 0, 0, 0, 0);
}

pub fn qoiGetIndexPos(pixel: QoiPixel) u6 {
    const r: u32 = pixel.vals.red;
    const g: u32 = pixel.vals.green;
    const b: u32 = pixel.vals.blue;
    const a: u32 = pixel.vals.alpha;
    return @truncate(r *% 3 +% g *% 5 +% b *% 7 +% a *% 11);
}

fn qoiEncInit(desc: *QoiDesc, enc: *QoiEnc, data: [*]u8) bool {
    for (0..64) |i| {
        qoiInitializePixel(&enc.buffer[i]);
    }

    enc.len = desc.width * desc.height; // don't need to cast to usize i think
    enc.pad = 0;
    enc.run = 0;
    enc.pixel_offset = 0;

    qoiSetPixelRGBA(&enc.prev_pixel, 0, 0, 0, 255);

    enc.data = data; // might have to cast to *u8 or something
    enc.offset = enc.data + 14;

    return true;
}

fn qoiEncDone(enc: *QoiEnc) bool {
    return enc.pixel_offset >= enc.len;
}

fn qoiEncRun(enc: *QoiEnc) void {
    const tag: u8 = @intFromEnum(QoiEnum.QOI_OP_RUN) | (enc.run - 1);
    enc.run = 0;

    enc.offset[0] = tag;
    enc.offset += 1;
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

fn qoiEncIndex(enc: *QoiEnc, index_pos: u8) void {
    const tag: u8 = @intFromEnum(QoiEnum.QOI_OP_INDEX) | index_pos;
    enc.offset[0] = tag;
    enc.offset += 1;
}

fn qoiEncRGB(enc: *QoiEnc, px: QoiPixel) void {
    const tags = [4]u8{
        @intFromEnum(QoiEnum.QOI_OP_RGB),
        px.vals.red,
        px.vals.green,
        px.vals.blue,
    };

    for (tags, 0..) |tag, i| {
        enc.offset[i] = tag;
    }

    enc.offset += 4;
}

fn qoiEncRGBA(enc: *QoiEnc, px: QoiPixel) void {
    const tags = [5]u8{
        @intFromEnum(QoiEnum.QOI_OP_RGBA),
        px.vals.red,
        px.vals.green,
        px.vals.blue,
        px.vals.alpha,
    };

    for (tags, 0..) |tag, i| {
        enc.offset[i] = tag;
    }

    enc.offset += 5;
}

fn qoiEncDifference(enc: *QoiEnc, red_diff: i32, green_diff: i32, blue_diff: i32) void {
    const green_diff_biased: u8 = @intCast(green_diff + 2); // could it matter that we are adding and then casting?
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

fn qoiEncLuma(enc: *QoiEnc, green_diff: i8, dr_dg: i8, db_dg: i8) void {
    const green_diff_biased: u8 = @intCast(green_diff + 32);
    const dr_dg_biased: u8 = @intCast(dr_dg + 8);
    const db_dg_biased: u8 = @intCast(db_dg + 8);

    const tags = [2]u8{ @intFromEnum(QoiEnum.QOI_OP_LUMA) | green_diff_biased, dr_dg_biased << 4 | db_dg_biased };

    for (tags, 0..) |tag, i| {
        enc.offset[i] = tag;
    }

    enc.offset += 2;
}

fn qoiEncodeChunk(desc: *QoiDesc, enc: *QoiEnc, qoi_pixel_bytes: [*]u8) void {
    // var cur_pixel_multi: [*]align(1) QoiPixel = @ptrCast(qoi_pixel_bytes);

    var cur_pixel: QoiPixel = undefined; // might need to handle this differently

    if (desc.channels < 4) {
        cur_pixel.vals.alpha = 255;
        @memcpy(cur_pixel.channels[0..3], qoi_pixel_bytes[0..3]);
    } else {
        @memcpy(&cur_pixel.channels, qoi_pixel_bytes[0..4]);
    }

    const index_pos: u6 = qoiGetIndexPos(cur_pixel);

    if (qoiComparePixel(cur_pixel, enc.prev_pixel, desc.channels)) {
        if (enc.run + 1 >= 62 or enc.pixel_offset >= enc.len) {
            qoiEncRun(enc);
        }
    } else {
        if (enc.run > 0) {
            qoiEncRun(enc);
        }
        if (qoiComparePixel(enc.buffer[index_pos], cur_pixel, 4)) {
            qoiEncIndex(enc, index_pos);
        } else {
            enc.buffer[index_pos] = cur_pixel;

            if (desc.channels > 3 and cur_pixel.vals.alpha != enc.prev_pixel.vals.alpha) {
                qoiEncRGBA(enc, cur_pixel);
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
                    qoiEncDifference(enc, @intCast(red_diff), @intCast(green_diff), @intCast(blue_diff));
                } else if (dr_dg >= -8 and dr_dg <= 7 and
                    green_diff >= -32 and green_diff <= 31 and
                    db_dg >= -8 and db_dg <= 7)
                {
                    qoiEncLuma(enc, @intCast(green_diff), @intCast(dr_dg), @intCast(db_dg));
                } else {
                    qoiEncRGB(enc, cur_pixel);
                }
            }
        }
    }

    enc.prev_pixel = cur_pixel;
    enc.pixel_offset += 1;

    if (qoiEncDone(enc)) {
        for (QOI_PADDING, 0..) |PAD, i| {
            enc.offset[i] = PAD;
        }
        enc.offset += 8;
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
    print("Image size: {d}\n", .{image_size});

    const bytes_read = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(bytes_read);
    // print("Bytes read: {d}\n", .{bytes_read});

    if (image_size < bytes_read.len) {
        print("{d} bytes are required for {s}. Your file is too small at {d} bytes.\n", .{ image_size, args[1], bytes_read.len });
    }

    var desc: QoiDesc = .{};

    _ = qoiSetDimensions(&desc, width, height);
    _ = qoiSetChannels(&desc, channels);
    _ = qoiSetColorspace(&desc, colorspace);

    const qoi_file_size = @as(usize, desc.width) * @as(usize, desc.height) * (@as(usize, desc.channels) + 1) + 14 + 8 + @sizeOf(usize);
    var qoi_file = try allocator.alloc(u8, qoi_file_size);
    defer allocator.free(qoi_file);

    print("Writing {s} ...\n", .{args[6]});

    _ = writeQoiHeader(&desc, qoi_file[0..14]);

    var pixel_seek: [*]u8 = bytes_read.ptr;
    var enc: QoiEnc = undefined;

    _ = qoiEncInit(&desc, &enc, qoi_file.ptr);

    while (!qoiEncDone(&enc)) {
        qoiEncodeChunk(&desc, &enc, pixel_seek);
        pixel_seek += desc.channels;
    }

    const outfile = try std.fs.cwd().createFile(args[6], .{ .truncate = true });
    defer outfile.close();
    _ = try outfile.writeAll(qoi_file);
}
