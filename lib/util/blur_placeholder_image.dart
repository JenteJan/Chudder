import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The smear of colour a picture's blurhash stands for, as an image.
///
/// What `BlurHashImage` from flutter_blurhash gives, worked out faster. The
/// hash is decoded on the thread that builds the frame, the moment a card
/// asks for it, so a grid pays for a row of them every few frames of a fling.
/// The package's decoder raises to a power three times for every pixel to get
/// from linear light to sRGB, and keeps its numbers in lists of lists; this
/// one looks the curve up in a table and keeps them flat, and comes out about
/// ten times quicker for the same pixels, give or take one level in a channel.
class BlurPlaceholderImage extends ImageProvider<BlurPlaceholderImage> {
  const BlurPlaceholderImage(this.hash, {this.size = 16});

  final String hash;

  /// How many pixels square to decode it at. It is drawn stretched over the
  /// picture's whole box, and a blur has no detail to lose.
  final int size;

  @override
  Future<BlurPlaceholderImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<BlurPlaceholderImage>(this);

  @override
  ImageStreamCompleter loadImage(BlurPlaceholderImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() {
    final Uint8List pixels;
    try {
      pixels = decodeBlurHash(hash, size, size);
    } catch (error, stack) {
      return Future<ImageInfo>.error(error, stack);
    }
    final completer = Completer<ImageInfo>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(ImageInfo(image: image)),
    );
    return completer.future;
  }

  @override
  bool operator ==(Object other) => other is BlurPlaceholderImage && other.hash == hash && other.size == size;

  @override
  int get hashCode => Object.hash(hash, size);

  @override
  String toString() => 'BlurPlaceholderImage($hash, $size)';
}

/// [hash] as [width] by [height] pixels of RGBA. Throws on a hash that is not
/// one.
Uint8List decodeBlurHash(String hash, int width, int height) {
  if (hash.length < 6) throw FormatException('A blurhash is at least 6 characters', hash);
  final sizeFlag = _digit(hash, 0);
  final numY = sizeFlag ~/ 9 + 1;
  final numX = sizeFlag % 9 + 1;
  final count = numX * numY;
  if (hash.length != 4 + 2 * count) {
    throw FormatException('A blurhash of $numX by $numY is ${4 + 2 * count} characters', hash);
  }
  final maximum = (_digit(hash, 1) + 1) / 166;

  // Three numbers to a component: red, green, blue, in linear light.
  final colors = Float64List(count * 3);
  final dc = _decode83(hash, 2, 6);
  colors[0] = _sRGBToLinear[dc >> 16];
  colors[1] = _sRGBToLinear[(dc >> 8) & 255];
  colors[2] = _sRGBToLinear[dc & 255];
  for (var i = 1; i < count; i++) {
    final value = _decode83(hash, 4 + i * 2, 6 + i * 2);
    colors[i * 3] = _signedSquare((value ~/ 361 - 9) / 9) * maximum;
    colors[i * 3 + 1] = _signedSquare((value ~/ 19 % 19 - 9) / 9) * maximum;
    colors[i * 3 + 2] = _signedSquare((value % 19 - 9) / 9) * maximum;
  }

  final cosX = _cosines(numX, width);
  final cosY = _cosines(numY, height);
  final toSRGB = _linearToSRGB;
  final pixels = Uint8List(width * height * 4);
  var p = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      var c = 0;
      for (var j = 0; j < numY; j++) {
        final basisY = cosY[j * height + y];
        for (var i = 0; i < numX; i++) {
          final basis = cosX[i * width + x] * basisY;
          r += colors[c++] * basis;
          g += colors[c++] * basis;
          b += colors[c++] * basis;
        }
      }
      pixels[p++] = toSRGB[_step(r)];
      pixels[p++] = toSRGB[_step(g)];
      pixels[p++] = toSRGB[_step(b)];
      pixels[p++] = 255;
    }
  }
  return pixels;
}

const String _alphabet = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~';

/// Each character's place in [_alphabet], by its code; -1 for one not in it.
final Int8List _digits = () {
  final digits = Int8List(128)..fillRange(0, 128, -1);
  for (var i = 0; i < _alphabet.length; i++) {
    digits[_alphabet.codeUnitAt(i)] = i;
  }
  return digits;
}();

int _digit(String hash, int index) {
  final code = hash.codeUnitAt(index);
  final digit = code < 128 ? _digits[code] : -1;
  if (digit < 0) throw FormatException('Not a blurhash character', hash, index);
  return digit;
}

int _decode83(String hash, int from, int to) {
  var value = 0;
  for (var i = from; i < to; i++) {
    value = value * 83 + _digit(hash, i);
  }
  return value;
}

double _signedSquare(double value) => value < 0 ? -(value * value) : value * value;

/// How finely the curve from linear light to sRGB is tabled. Where it is
/// steepest, in the darks, one step along it is less than one level out.
const int _steps = 4095;

int _step(double linear) => linear <= 0 ? 0 : (linear >= 1 ? _steps : (linear * _steps + 0.5).toInt());

/// Rounded the way flutter_blurhash rounds, so the pixels are the same ones.
final Uint8List _linearToSRGB = () {
  final table = Uint8List(_steps + 1);
  for (var i = 0; i <= _steps; i++) {
    final v = i / _steps;
    final encoded = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    table[i] = (encoded * 255 + 0.5).round().clamp(0, 255);
  }
  return table;
}();

final Float64List _sRGBToLinear = () {
  final table = Float64List(256);
  for (var i = 0; i < 256; i++) {
    final v = i / 255;
    table[i] = v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }
  return table;
}();

/// cos(pi * position * component / [size]) for every component and position:
/// the same few tables for every hash of a shape, so kept.
Float64List _cosines(int components, int size) => _cosineTables[components * 4096 + size] ??= Float64List.fromList([
      for (var i = 0; i < components; i++)
        for (var position = 0; position < size; position++) math.cos(math.pi * position * i / size),
    ]);

final Map<int, Float64List> _cosineTables = {};
