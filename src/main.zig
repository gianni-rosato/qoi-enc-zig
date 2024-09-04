const std = @import("std");
const print = std.debug.print;
const parseInt = std.fmt.parseInt;
const writeInt = std.mem.writeInt;
const eql = std.mem.eql;

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

const QoiPixel = extern union {
    vals: extern struct {
        red: u8,
        green: u8,
        blue: u8,
        alpha: u8,
    },
    channels: [4]u8,
    concatenated_pixel_values: u32,
};

const QoiDesc = struct {
    width: u32 = 0,
    height: u32 = 0,
    channels: u8 = 0,
    colorspace: u8 = 0,

    fn writeQoiHeader(self: QoiDesc, dest: *[14]u8) void {
        @memcpy(dest[0..4], QOI_MAGIC);
        writeInt(u32, dest[4..8], self.width, .big);
        writeInt(u32, dest[8..12], self.height, .big);
        dest[12] = self.channels;
        dest[13] = self.colorspace;
    }
};

const QoiEnc = struct {
    buffer: [64]QoiPixel,
    prev_pixel: QoiPixel,

    pixel_offset: usize,
    len: usize,

    data: [*]u8,
    offset: [*]u8,

    run: u8,
    pad: u24,

    fn qoiEncInit(self: *QoiEnc, desc: QoiDesc, data: [*]u8) !void {
        for (0..64) |i| {
            for (0..3) |j| self.buffer[i].channels[j] = 0;
            self.buffer[i].vals.alpha = 255;
        }

        self.len = desc.width * desc.height;
        self.pad = 0;
        self.run = 0;
        self.pixel_offset = 0;

        for (0..3) |i| self.prev_pixel.channels[i] = 0;
        self.prev_pixel.vals.alpha = 255;

        self.data = data;
        self.offset = self.data + 14;
    }
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
        const qoi_opcode: u8 = if (channels > 3) @intFromEnum(QoiEnum.QOI_OP_RGBA) else @intFromEnum(QoiEnum.QOI_OP_RGB);
        const tags = [_]u8{ qoi_opcode, px.vals.red, px.vals.green, px.vals.blue, px.vals.alpha };
        for (tags[0 .. channels + 1], 0..channels + 1) |tag, i| enc.offset[i] = tag;
        enc.offset += channels + 1;
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
    fn finishEncodeChunk(enc: *QoiEnc, cur_pixel: QoiPixel) void {
        enc.prev_pixel = cur_pixel;
        enc.pixel_offset += 1;

        if (enc.pixel_offset >= enc.len) {
            @memcpy(enc.offset[0..QOI_PADDING.len], QOI_PADDING);
            enc.offset += QOI_PADDING.len;
        }
    }
};

fn printHelp() !void {
    print("Freestanding QOI Encoder in \x1b[33mZig\x1b[0m\n", .{});
    print("Example usage: qoi-zig [input.pam] [output] [colorspace] [color_depth] [dither]\n", .{});
    print("Colorspace:\n\t0: sRGB w/ Linear Alpha\n\t1: Linear RGB\n", .{});
    print("Color Depth:\n\t0: Same as Source\n\t*: Palletize\n", .{});
    print("Dithering:\n\t0: None\n\t1: Sierra Lite\n", .{});
}

fn parsePamHeader(bytes_read: []u8, width: *u32, height: *u32, channels: *u8) !usize {
    var header_tokens = std.mem.tokenizeAny(u8, bytes_read[0..], " \n\r");
    var widthOffset: usize = undefined;
    var heightOffset: usize = undefined;
    var i: u4 = 0;
    while (true) : (i += 1) {
        const token = header_tokens.next();
        if (token == null or token.?.len == 0) break;
        switch (i) {
            2 => {
                width.* = try parseInt(u32, token.?, 10);
                widthOffset = token.?.len - 1;
            },
            4 => {
                height.* = try parseInt(u32, token.?, 10);
                heightOffset = token.?.len - 1;
            },
            6 => channels.* = try parseInt(u8, token.?, 10),
            8 => if (try parseInt(u16, token.?, 10) > 255) return error.OutOfBounds else {},
            else => {},
        }
    }
    print("Dimensions: {d}x{d} | \x1b[31mR\x1b[0m\x1b[32mG\x1b[0m\x1b[34mB\x1b[0m", .{ width.*, height.* });
    if (channels.* > 3) print("\x1b[37mA\x1b[0m", .{});

    var offset: usize = 59;
    if (channels.* > 3) offset += 6;
    offset += widthOffset + heightOffset;
    return offset;
}

fn qoiComparePixel(pixel1: QoiPixel, pixel2: QoiPixel) bool {
    return pixel1.concatenated_pixel_values == pixel2.concatenated_pixel_values;
}

fn qoiEncodeChunk(desc: *QoiDesc, enc: *QoiEnc, qoi_pixel_bytes: [*]u8) void {
    var cur_pixel: QoiPixel = undefined;

    if (desc.channels < 4) {
        cur_pixel.vals.alpha = 255;
        @memcpy(cur_pixel.channels[0..3], qoi_pixel_bytes[0..3]);
    } else {
        @memcpy(&cur_pixel.channels, qoi_pixel_bytes[0..4]);
    }

    if (qoiComparePixel(cur_pixel, enc.prev_pixel)) {
        enc.run += 1;
        if (enc.run >= 62 or enc.pixel_offset >= enc.len) enc.qoiEncRun();
        enc.finishEncodeChunk(cur_pixel);
        return;
    }

    if (enc.run > 0) enc.qoiEncRun();

    const index_pos: u6 = @truncate(cur_pixel.vals.red *% 3 +% cur_pixel.vals.green *% 5 +% cur_pixel.vals.blue *% 7 +% cur_pixel.vals.alpha *% 11);

    if (qoiComparePixel(enc.buffer[index_pos], cur_pixel)) {
        enc.qoiEncIndex(index_pos);
        enc.finishEncodeChunk(cur_pixel);
        return;
    }

    enc.buffer[index_pos] = cur_pixel;

    if (cur_pixel.vals.alpha != enc.prev_pixel.vals.alpha) {
        enc.qoiEncFullColor(cur_pixel, desc.channels);
        enc.finishEncodeChunk(cur_pixel);
        return;
    }

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

    enc.finishEncodeChunk(cur_pixel);
}

fn palletizeInput(pixel_seek: [*]u8, total_pixels: u32, channels: u8, quantize_factor: u16) void {
    for (0..total_pixels) |p| {
        const o = p * channels;
        for (0..channels) |c| {
            pixel_seek[o + c] = @intCast(pixel_seek[o + c] / quantize_factor * quantize_factor);
        }
    }
}

fn sierraLite(pixel_seek: [*]u8, width: u32, height: u32, channels: u8, quantize_factor: u16) void {
    var error_buffer = [_]f32{0} ** 3;

    for (0..height) |y| {
        for (0..width) |x| {
            const pixel_index = (y * width + x) * channels;
            var new_pixel: [3]u8 = undefined;

            for (0..3) |c| {
                var pixel_value: f32 = @floatFromInt(pixel_seek[pixel_index + c]);
                pixel_value += error_buffer[c];

                const qv: i32 = @intFromFloat(@round(pixel_value / @as(f32, @floatFromInt(quantize_factor))) * @as(f32, @floatFromInt(quantize_factor)));
                const quantized_value: u8 = @intCast(std.math.clamp(qv, 0, 255));

                new_pixel[c] = quantized_value;
                const quantization_error: f32 = pixel_value - @as(f32, @floatFromInt(quantized_value));

                // Distribute the error according to Sierra Lite filter
                error_buffer[c] = 0; // Reset error buffer for next pixel

                if (x < width - 1) {
                    const index = (y * width + (x + 1)) * channels + c;
                    const pix: i16 = @intFromFloat(@as(f32, @floatFromInt(pixel_seek[index])) + quantization_error * (2.0 / 4.0));
                    pixel_seek[index] = @intCast(std.math.clamp(pix, 0, 255));
                }

                if (y < height - 1) {
                    if (x > 0) {
                        const index = ((y + 1) * width + (x - 1)) * channels + c;
                        const pix: i16 = @intFromFloat(@as(f32, @floatFromInt(pixel_seek[index])) + quantization_error * (1.0 / 4.0));
                        pixel_seek[index] = @intCast(std.math.clamp(pix, 0, 255));
                    }
                    const index = ((y + 1) * width + x) * channels + c;
                    const pix: i16 = @intFromFloat(@as(f32, @floatFromInt(pixel_seek[index])) + quantization_error * (1.0 / 4.0));
                    pixel_seek[index] = @intCast(std.math.clamp(pix, 0, 255));
                }
            }

            // Update the pixel values
            for (0..3) |c| {
                pixel_seek[pixel_index + c] = new_pixel[c];
            }
        }
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

    if (args.len < 2) {
        print("Usage: qoi-zig [input.pam] [output] [colorspace] [color_depth] [dither]\n", .{});
        print("Help: qoi-zig -h\n", .{});
        return;
    }

    if (eql(u8, args[1], "-h") or
        eql(u8, args[1], "--help") or
        args.len != 6 or
        args[1].len < 1)
    {
        _ = try printHelp();
        return;
    }

    var width: u32 = undefined;
    var height: u32 = undefined;
    var channels: u8 = undefined;
    const colorspace: u8 = try parseInt(u2, args[3], 10);
    const color_depth: u16 = try parseInt(u16, args[4], 10);
    const dither: u8 = try parseInt(u2, args[5], 10);

    print("Opening {s} ... ", .{args[1]});

    const file = try std.fs.cwd().openFile(args[1], .{ .mode = .read_only });
    defer file.close();

    const bytes_read = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(bytes_read);
    var offset: usize = 0;

    if (eql(u8, bytes_read[0..2], "P7")) {
        print("file is a PAM\n", .{});
        offset = try parsePamHeader(bytes_read[0..72], &width, &height, &channels);
    } else {
        print("\n\x1b[31mInvalid Input: Input file does not appear to be a compatible PAM.\x1b[0m\n", .{});
        print("If your PAM input contains comments in the header, please strip them.\n", .{});
        return error.InvalidInput;
    }

    const image_size: usize = width * height * channels;
    if (image_size > bytes_read.len - offset) {
        print("\x1b[31mInvalid Input: Image size is larger than the file size.\x1b[0m\n", .{});
        return error.InvalidInput;
    }

    var desc: QoiDesc = .{ .width = width, .height = height, .channels = channels, .colorspace = colorspace };

    const qoi_file_size = @as(usize, desc.width) * @as(usize, desc.height) * (@as(usize, desc.channels) + 1) + 14 + 8 + @sizeOf(usize);
    var qoi_file = try allocator.alloc(u8, qoi_file_size);
    defer allocator.free(qoi_file);

    var pixel_seek: [*]u8 = bytes_read[offset..].ptr;

    switch (color_depth) {
        0 => {
            print(" | Lossless\n", .{});
        },
        else => {
            print(" | Lossy ({d}-bit pallette, ", .{color_depth});
            const quantize_factor: u16 = @as(u16, 256) / color_depth;
            switch (dither) {
                0 => {
                    print("no dithering)\n", .{});
                    const total_pixels: u32 = width * height;
                    palletizeInput(pixel_seek, total_pixels, channels, quantize_factor);
                },
                else => {
                    print("dithering)\n", .{});
                    sierraLite(pixel_seek, width, height, channels, quantize_factor);
                },
            }
        },
    }

    var enc: QoiEnc = undefined;

    print("Writing {s} ... ", .{args[2]});

    desc.writeQoiHeader(qoi_file[0..14]);

    try enc.qoiEncInit(desc, qoi_file.ptr);

    while (!(enc.pixel_offset >= enc.len)) {
        qoiEncodeChunk(&desc, &enc, pixel_seek);
        pixel_seek += desc.channels;
    }

    const used_len = @intFromPtr(enc.offset) - @intFromPtr(enc.data);

    const outfile = try std.fs.cwd().createFile(args[2], .{ .truncate = true });
    defer outfile.close();
    _ = try outfile.writeAll(enc.data[0..used_len]);
    print("\x1b[32mSuccess!\x1b[0m\n\tOriginal:\t{d} bytes\n\tCompressed:\t{d} bytes ", .{ image_size + offset, used_len });
    if ((image_size + offset) > used_len) {
        const used_len_flt: f64 = @floatFromInt(used_len);
        const image_size_flt: f64 = @floatFromInt(image_size + offset);
        const percent_dec: f64 = 100.0 - ((used_len_flt / image_size_flt) * 100.0);
        print("(\x1b[33m{d:.2}%\x1b[0m smaller)\n", .{percent_dec});
    } else {
        print("\n", .{});
    }
}
