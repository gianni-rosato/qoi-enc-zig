# QOI Image Encoder in Zig

This Zig program encodes RGB images into the Quite OK Image Format (QOI). It is a freestanding implementation, existing entirely in one file. The QOI format is a simple, lossless image format designed for fast encoding and decoding.

![qoi-logo-white](https://ninja.dog/1nzHoy.svg)

## Program Details

I wrote this mostly as a learning exercise, so I hope that the details below can help you learn from this implementation as well. I was heavily inspired by the [Simplified QOI Codec Library](https://github.com/Aftersol/Simplified-QOI-Codec), a one header file library for encoding and decoding QOI files written in C.

### Data Structures

- `QoiEnum`: Opcodes used in the QOI format.
- `QoiDesc`: Describes the properties of a QOI image, including its width, height, number of color channels, and colorspace.
- `QoiPixel`: Represents a pixel in a QOI image. It can be accessed as individual color channels or as a single 32-bit integer.
- `QoiEnc`: A structure that holds the state of the QOI encoder as it traverses the input file.

## Usage

The program is run from the command line with the following arguments:

```
qoi_enc <filename> <width> <height> <channels> <colorspace> <output>
```

- `<filename>`: The path to the input RGB image file.
- `<width>` and `<height>`: The dimensions of the image.
- `<channels>`: The number of color channels in the image. Use `3` for RGB and `4` for RGBA.
- `<colorspace>`: The colorspace of the image. Use `0` for sRGB with linear alpha and `1` for linear RGB.
- `<output>`: The path to the output QOI image file.

If the input file is too small for the specified image dimensions & channels, an error message is printed.

## Examples

There are some RGB examples provided in the `examples/` directory. You can use these to test the program and see how it works.

Encode `foo.rgb` with dimensions 512x512:

```bash
qoi-zig foo.rgb 512 512 3 0 foo.qoi
```
Encode `squoosh.rgb` with dimensions 600x600:

```bash
qoi-zig squoosh.rgb 600 600 3 0 squoosh.qoi
```

This will create a QOI image file from the input RGB image file. The original and compressed file sizes are printed upon successful encoding.

This program does not perform any error checking on the input file. It is assumed that the file is a valid RGB or RGBA image with the specified dimensions and colorspace. Incorrect input can lead to unexpected results or program crashes. Always ensure that your input data is correct before running the program.

## Dependencies

This program requires the Zig programming language, at least version `0.12.0-dev.2922`. It also uses the standard library provided with Zig. No other dependencies are required.

## Building

To build the program, navigate to the directory `qoi-enc-zig` and run:

```
zig build
```

This will create an executable file `qoi-zig` in `zig-out/bin/`. You can then run this file with the appropriate arguments to encode your images like so:

```bash
./zig-out/bin/qoi-zig examples/squoosh.rgb 600 600 3 0 squoosh.qoi
```

## License

This program is released under the BSD 3-Clause License. You are free to use, modify, and distribute the program under the terms of this license.

## Acknowledgments

Thank you to the authors of the Simplified QOI Codec Library, and Cancername for their expert consulting on the Zig programming language! Much appreciated!

- [QOI Specification](https://qoiformat.org/qoi-specification.pdf)
- [QOI Site](https://qoiformat.org/)
- [Zig](https://ziglang.org/)
