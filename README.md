# QOI Image Encoder in Zig

This Zig program encodes a subset of Portable Arbitrary Map (PAM) images into the Quite OK Image Format (QOI). It is a freestanding implementation, existing entirely in one file. The QOI format is a simple, lossless image format designed for fast encoding and decoding.

<div align="center">
<img src="https://ninja.dog/1nzHoy.svg" alt="QOI Logo" width=230/>
</div>

## Program Details

I wrote this mostly as a learning exercise, and I was heavily inspired by the [Simplified QOI Codec Library](https://github.com/Aftersol/Simplified-QOI-Codec), a one header file library for encoding and decoding QOI files written in C.

### Benchmarks

These are some rudimentary, unscientific benchmarks performed on a Linux system running a Core i7-13700k with the [`poop`](https://github.com/andrewrk/poop) benchmarking utility. The `qoi-zig` binary was built in ReleaseFast mode, and we're using FFmpeg n6.1.1 from the Arch repos.

1. This first benchmark was run on a `big2.pam` image that I haven't included in the `examples` directory because it is rather large at 59.8 MB for a massive 5468x3644 image. I'll link a lossless JPEG-XL encode [here](https://files.catbox.moe/80aib5.jxl) if you'd like to take a look for yourself.
```bash
13700k :: ~ » poop -d 25000 'ffmpeg -y -i big2.pam -frames:v 1 big2.qoi' 'qoi-zig big2.pam big2.qoi 0'
Benchmark 1 (104 runs): ffmpeg -y -i big2.pam -frames:v 1 big2.qoi
  measurement          mean ± σ            min … max           outliers         delta
  wall_time           242ms ± 8.53ms     229ms …  277ms          2 ( 2%)        0%
  peak_rss            244MB ±  261KB     243MB …  245MB          7 ( 7%)        0%
  cpu_cycles          945M  ± 10.2M      877M  …  961M           9 ( 9%)        0%
  instructions       2.11G  ± 17.2M     1.96G  … 2.12G          13 (13%)        0%
  cache_references   5.66M  ±  432K     3.88M  … 5.98M          23 (22%)        0%
  cache_misses       3.42M  ±  320K     2.04M  … 3.66M          13 (13%)        0%
  branch_misses      15.7M  ±  136K     14.5M  … 15.8M          13 (13%)        0%
Benchmark 2 (128 runs): qoi-zig big2.pam big2.qoi 0
  measurement          mean ± σ            min … max           outliers         delta
  wall_time           196ms ± 3.80ms     185ms …  211ms          6 ( 5%)        ⚡- 18.7% ±  0.7%
  peak_rss            119MB ±  654KB     118MB …  121MB          0 ( 0%)        ⚡- 51.0% ±  0.1%
  cpu_cycles          756M  ± 3.83M      741M  …  772M           8 ( 6%)        ⚡- 20.0% ±  0.2%
  instructions       1.82G  ± 3.34M     1.79G  … 1.82G          11 ( 9%)        ⚡- 13.7% ±  0.1%
  cache_references   6.07M  ±  109K     5.23M  … 6.15M          12 ( 9%)        💩+  7.1% ±  1.4%
  cache_misses       2.22M  ± 68.3K     2.07M  … 2.57M           6 ( 5%)        ⚡- 35.2% ±  1.7%
  branch_misses      15.2M  ± 48.5K     14.9M  … 15.4M           6 ( 5%)        ⚡-  3.3% ±  0.2%
```

2. This benchmark was performed on the `qoi_logo.pam` image included in this repo's `examples` directory.
```bash
13700k :: ~ » poop 'ffmpeg -y -i qoi_logo.pam -frames:v 1 qoi_logo.qoi' 'qoi-zig qoi_logo.pam qoi_logo.qoi 0'
Benchmark 1 (178 runs): ffmpeg -y -i qoi_logo.pam -frames:v 1 qoi_logo.qoi
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          28.1ms ± 3.17ms    25.5ms … 42.5ms         17 (10%)        0%
  peak_rss           54.3MB ±  311KB    53.5MB … 55.0MB          0 ( 0%)        0%
  cpu_cycles         91.0M  ± 2.03M     72.5M  … 93.6M          11 ( 6%)        0%
  instructions        159M  ± 3.45M      124M  …  161M          21 (12%)        0%
  cache_references    675K  ± 27.4K      534K  …  765K           9 ( 5%)        0%
  cache_misses        226K  ± 16.7K      133K  …  254K           4 ( 2%)        0%
  branch_misses       647K  ± 15.3K      506K  …  675K          19 (11%)        0%
Benchmark 2 (3107 runs): qoi-zig qoi_logo.pam qoi_logo.qoi 0
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          1.55ms ±  537us     227us … 11.6ms        262 ( 8%)        ⚡- 94.5% ±  0.5%
  peak_rss            844KB ± 28.3KB     635KB …  848KB         87 ( 3%)        ⚡- 98.4% ±  0.0%
  cpu_cycles         66.1K  ± 59.7K        0   …  186K           0 ( 0%)        ⚡- 99.9% ±  0.1%
  instructions        142K  ±  137K        0   …  281K           0 ( 0%)        ⚡- 99.9% ±  0.1%
  cache_references    447   ±  296         0   … 1.58K          23 ( 1%)        ⚡- 99.9% ±  0.1%
  cache_misses       2.69   ± 4.68         0   …   93          197 ( 6%)        ⚡-100.0% ±  0.3%
  branch_misses       666   ±  624         0   … 1.70K           0 ( 0%)        ⚡- 99.9% ±  0.1%
```

FFmpeg is pretty fast, but it is evident there is more going on under the hood there. Even so, we'll take what we can get!

## Building

In order to build this program, you will need to have the latest version of the Zig programming language (at least version `0.12.0-dev.2922`) installed on your system as well as `git`. You can find instructions for installing Zig on the [official website](https://ziglang.org/). Once that is set up, follow the steps below for building the `qoi-zig` binary:

```bash
git clone https://github.com/gianni-rosato/qoi-enc-zig # Clone the repo
cd qoi-enc-zig # Enter the directory
zig build -Doptimize=ReleaseFast # Build the program
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

This program does not perform any error checking on the input file. It is assumed that the file is a compatible PAM file. Incorrect inputs can lead to unexpected results or program crashes; always ensure that your input data is correct before running the program.

## Dependencies

This program requires the Zig programming language, at least version `0.12.0`. It also uses the standard library provided with Zig. No other dependencies are required.

## License

This program is released under the BSD 3-Clause License. You are free to use, modify, and distribute the program under the terms of this license.

## Acknowledgments

Thank you to the authors of the Simplified QOI Codec Library, and Cancername for their expert consulting on the Zig programming language! Much appreciated!

- [QOI Specification](https://qoiformat.org/qoi-specification.pdf)
- [QOI Site](https://qoiformat.org/)
- [Zig](https://ziglang.org/)
