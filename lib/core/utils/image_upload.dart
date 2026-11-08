import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http_parser/http_parser.dart';

/// Normalized JPEG/PNG ready for API upload (HEIC/HEIF converted).
class PreparedUploadImage {
  const PreparedUploadImage({
    required this.path,
    required this.filename,
    required this.contentType,
  });

  final String path;
  final String filename;
  final MediaType contentType;
}

bool _isJpegName(String lower) => lower.endsWith('.jpg') || lower.endsWith('.jpeg');
bool _isPngName(String lower) => lower.endsWith('.png');

bool _looksLikeJpeg(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

bool _looksLikePng(Uint8List bytes) =>
    bytes.length > 7 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

bool _looksLikeHeic(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') return false;
  final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
  return const {'heic', 'heif', 'mif1', 'msf1', 'hevx', 'hevc'}.contains(brand);
}

String _baseName(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name.isEmpty ? 'image' : name;
  return name.substring(0, dot);
}

Future<Uint8List> _readHead(File file) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, 64)) {
    builder.add(chunk);
    if (builder.length >= 64) break;
  }
  return builder.takeBytes();
}

/// Returns a JPEG/PNG path suitable for API upload (converts HEIC/HEIF/WebP/etc).
Future<PreparedUploadImage> prepareImageForUpload(
  String path, {
  String? preferredName,
}) async {
  final file = File(path);
  if (!await file.exists()) {
    throw const FormatException('Файл изображения не найден');
  }

  final lower = path.toLowerCase();
  final head = await _readHead(file);
  final jpegByContent = _looksLikeJpeg(head);
  final pngByContent = _looksLikePng(head);
  final heicByContent = _looksLikeHeic(head);

  if (!heicByContent && (jpegByContent || _isJpegName(lower))) {
    final rawName = preferredName ?? '${_baseName(path)}.jpg';
    final name = (rawName.toLowerCase().endsWith('.jpg') || rawName.toLowerCase().endsWith('.jpeg'))
        ? rawName
        : '$rawName.jpg';
    return PreparedUploadImage(
      path: path,
      filename: name,
      contentType: MediaType('image', 'jpeg'),
    );
  }

  if (!heicByContent && (pngByContent || _isPngName(lower))) {
    final rawName = preferredName ?? '${_baseName(path)}.png';
    final name = rawName.toLowerCase().endsWith('.png') ? rawName : '$rawName.png';
    return PreparedUploadImage(
      path: path,
      filename: name,
      contentType: MediaType('image', 'png'),
    );
  }

  final outPath =
      '${Directory.systemTemp.path}/th_${DateTime.now().microsecondsSinceEpoch}.jpg';
  final compressed = await FlutterImageCompress.compressAndGetFile(
    path,
    outPath,
    quality: 88,
    format: CompressFormat.jpeg,
  );
  if (compressed != null && await File(compressed.path).exists()) {
    final rawName = preferredName ?? 'image.jpg';
    final name = (rawName.toLowerCase().endsWith('.jpg') || rawName.toLowerCase().endsWith('.jpeg'))
        ? rawName
        : '$rawName.jpg';
    return PreparedUploadImage(
      path: compressed.path,
      filename: name,
      contentType: MediaType('image', 'jpeg'),
    );
  }

  final raw = await file.readAsBytes();
  try {
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (png == null) throw const FormatException('decode failed');
    final pngPath =
        '${Directory.systemTemp.path}/th_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(pngPath).writeAsBytes(png.buffer.asUint8List(), flush: true);
    final rawName = preferredName ?? 'image.png';
    final name = rawName.toLowerCase().endsWith('.png') ? rawName : '$rawName.png';
    return PreparedUploadImage(
      path: pngPath,
      filename: name,
      contentType: MediaType('image', 'png'),
    );
  } catch (_) {
    throw const FormatException(
      'Не удалось обработать изображение. Выберите JPEG, PNG или HEIC с iPhone.',
    );
  }
}

Future<MultipartFile> multipartImageFromPath(
  String path, {
  String? filename,
}) async {
  final prepared = await prepareImageForUpload(path, preferredName: filename);
  return MultipartFile.fromFile(
    prepared.path,
    filename: prepared.filename,
    contentType: prepared.contentType,
  );
}

/// Photo picker that accepts iPhone HEIC/HEIF and normalizes to JPEG/PNG for preview + upload.
Future<PreparedUploadImage?> pickPreparedImage() async {
  // FileType.image opens the Photos UI on iOS (includes HEIC).
  final files = await FilePicker.pickFiles(type: FileType.image);
  if (files.isEmpty) return null;
  final path = files.first.path;
  if (path == null || path.isEmpty) return null;
  return prepareImageForUpload(path);
}
