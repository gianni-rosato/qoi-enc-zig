# QOI Image Encoder in Zig

This Zig program encodes a subset of Portable Arbitrary Map (PAM) images into the Quite OK Image Format (QOI). It is a freestanding implementation, existing entirely in one file. The QOI format is a simple, lossless image format designed for fast encoding and decoding.

<div align="center">
<img src="https://ninja.dog/1nzHoy.svg" alt="QOI Logo" width=230/>
</div>

## Program Details

I wrote this mostly as a learning exercise, so I hope that the details below can help you learn from this implementation as well. I was heavily inspired by the [Simplified QOI Codec Library](https://github.com/Aftersol/Simplified-QOI-Codec), a one header file library for encoding and decoding QOI files written in C.

### Data Structures

- `QoiEnum`: Opcodes used in the QOI format.
- `QoiDesc`: Describes the properties of a QOI image, including its width, height, number of color channels, and colorspace.
- `QoiPixel`: Represents a pixel in a QOI image. It can be accessed as individual color channels or as a single 32-bit integer.
- `QoiEnc`: A structure that holds the state of the QOI encoder as it traverses the input file.

## Building

In order to build this program, you will need to have the latest version of the Zig programming language (at least version `0.12.0-dev.2922`) installed on your system as well as `git`. You can find instructions for installing Zig on the [official website](https://ziglang.org/). Once that is set up, follow the steps below for building the `qoi-zig` binary:

```bash
git clone https://github.com/gianni-rosato/qoi-enc-zig # Clone the repo
cd qoi-enc-zig # Enter the directory
zig build # Build the program
```

*Note: A previous version of this program encoded RGB source images, and had a smaller codebase. If you'd like to build that verion, simply run `git reset --hard 36317c52896d8642ae10c3c18774991f4f68bf22` in the cloned directory before running `zig build`. The old README.md will also be present in the reset directory if you would like to see the old usage instructions.*

## Usage

The program is run from the command line with the following arguments:

```bash
qoi-zig [input.pam] [output] [colorspace]
```

- `input.pam`: The input PAM image file to encode.
- `output`: The output QOI image file to create.
- `colorspace`: The colorspace of the image. Use `0` for sRGB with linear alpha and `1` for linear RGB.

If the input file is too small for the specified image dimensions & channels, an error message is printed.

## Creating PAM Files

If you're just interested in testing this program, you can use the PAM files in the `examples/` directory. If you want to create your own PAM files, you can use [FFmpeg](https://wiki.x266.mov/docs/utilities/ffmpeg) like so:

Create an 8-bit RGB PAM file from an input image:

```bash
ffmpeg -i [input] -pix_fmt rgb24 -c pam -update 1 -f image2 output_rgb.pam
```

Create an 8-bit RGBA PAM file from an input image:

```bash
ffmpeg -i [input] -pix_fmt rgba -c pam -update 1 -f image2 output_rgba.pam
```

Note: This program's encoder will only encode 8-bit PAM files with 3 or 4 color channels. It will not encode 16-bit PAM files or PAM files with more than 4 color channels.

## Examples

There are some compatible PAM examples provided in the `examples/` directory. You can use these to test the program and see how it works.

Encode `plants.pam` in sRGB with linear alpha:

```bash
qoi-zig plants.pam plants.qoi 0
```

Encode `photograph.pam` in linear RGB (even though this image is meant to be encoded in sRGB w/ linear alpha):

```bash
qoi-zig photograph.pam photograph.qoi 1
```

These commands will create QOI image files from the inputs shown. The original and compressed file sizes are printed upon successful encoding.

This program does not perform any error checking on the input file. It is assumed that the file is a compatible PAM file. Incorrect input can lead to unexpected results or program crashes; always ensure that your input data is correct before running the program.

## Dependencies

This program requires the Zig programming language, at least version `0.12.0-dev.2922`. It also uses the standard library provided with Zig. No other dependencies are required.

## License

This program is released under the BSD 3-Clause License. You are free to use, modify, and distribute the program under the terms of this license.

## Acknowledgments

Thank you to the authors of the Simplified QOI Codec Library, and Cancername for their expert consulting on the Zig programming language! Much appreciated!

- [QOI Specification](https://qoiformat.org/qoi-specification.pdf)
- [QOI Site](https://qoiformat.org/)
- [Zig](https://ziglang.org/)
