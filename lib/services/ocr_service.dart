import "dart:io";
import "dart:typed_data";
import "package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart";
import "package:image/image.dart" as img;
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<List<String>> scanImage(File imageFile, int digits) async {
    final input = InputImage.fromFile(imageFile);
    final recognized = await _textRecognizer.processImage(input);
    return _extractCodes(recognized.text, digits);
  }

  List<String> _extractCodes(String text, int digits) {
    final normalized = text.replaceAll(RegExp(r"[^0-9]"), "");
    final re = RegExp(r"\d{" + digits.toString() + r"}");
    final matches = re.allMatches(normalized).map((m) => m.group(0)!).toList();
    final seen = <String>{};
    return matches.where((c) => seen.add(c)).toList();
  }

  Future<File> cropCenterForOcr(String imagePath, double widthFactor, double heightFactor) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception("Could not decode image.");

    final w = decoded.width;
    final h = decoded.height;

    final cropW = (w * widthFactor).round();
    final cropH = (h * heightFactor).round();
    final x = ((w - cropW) / 2).round();
    final y = ((h - cropH) / 2).round();

    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: cropW,
      height: cropH,
    );

    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(
      tempDir.path,
      "ocr_crop_${DateTime.now().millisecondsSinceEpoch}.jpg",
    );
    final outFile = File(outPath);
    await outFile.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(cropped, quality: 95)),
    );
    return outFile;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
