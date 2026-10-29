import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Tap-to-pick image box. Shows a freshly picked file, else the existing
/// remote image, else a placeholder prompt.
class ImagePickerField extends StatelessWidget {
  const ImagePickerField({
    super.key,
    required this.pickedFile,
    required this.existingUrl,
    required this.onPicked,
    this.size = 140,
    this.label = 'Add photo',
  });

  final File? pickedFile;
  final String? existingUrl;
  final ValueChanged<File> onPicked;
  final double size;
  final String label;

  Future<void> _pick(BuildContext context) async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (picked != null) {
        onPicked(File(picked.path));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open your photos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final File? file = pickedFile;
    final String? url = existingUrl;

    final Widget content;
    if (file != null) {
      content = Image.file(file, fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      content = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    } else {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.add_a_photo_outlined),
          const SizedBox(height: 6),
          Text(label),
        ],
      );
    }

    return GestureDetector(
      onTap: () => _pick(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: size,
          height: size,
          color: Colors.white,
          child: content,
        ),
      ),
    );
  }
}
