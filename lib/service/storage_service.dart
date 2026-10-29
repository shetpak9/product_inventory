import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Image hosting via Cloudinary (free tier, unsigned uploads).
class StorageService {
  // Fill these in from your Cloudinary dashboard.
  static const String _cloudName = 'zjx4o7nv';
  static const String _uploadPreset = 'product_inventory';

  /// Uploads [file] and returns its https URL. [path] is used as the
  /// Cloudinary folder (everything before the last '/').
  Future<String> uploadImage({required String path, required File file}) async {
    final Uri uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );

    final http.MultipartRequest request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset;

    final int slash = path.lastIndexOf('/');
    if (slash > 0) {
      request.fields['folder'] = path.substring(0, slash);
    }
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final http.StreamedResponse response =
        await request.send().timeout(const Duration(seconds: 60));
    final String body = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      debugPrint('Cloudinary upload failed: ${response.statusCode} $body');
      throw Exception('Image upload failed (${response.statusCode}).');
    }

    final Object? decoded = jsonDecode(body);
    final String? url = decoded is Map ? decoded['secure_url'] as String? : null;
    if (url == null) {
      throw Exception('Image upload failed: no URL returned.');
    }
    return url;
  }

  /// Unsigned uploads can't be deleted from the app, so this does nothing.
  Future<void> deleteByUrl(String url) async {
    debugPrint('Skipping remote delete for $url');
  }
}