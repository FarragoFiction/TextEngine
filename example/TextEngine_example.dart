import "dart:io";

import 'package:TextEngine/TextEngine.dart';

void main() {
    TextEngine engine = new TextEngine();

    String path = Directory.current.path;
    print(path);
    Uri uri = new Uri.file(path);
    print(uri.toFilePath());
}
