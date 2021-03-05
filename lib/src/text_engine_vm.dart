import "dart:io";

import "text_engine.dart" as ParentInterface;
import "wordlistfilebuilder.dart";

class TextEngine extends ParentInterface.TextEngine {

    TextEngine.create([int? seed, String wordListPath = ParentInterface.TextEngine.defaultWordListPath]) : super.create(seed, wordListPath);

    @override
    Future<ParentInterface.WordListFile> loadListFile(String path) async {
        if (Platform.isWindows) { path = path.replaceAll("/", "\\"); }
        final File file = new File(path);
        return WordListFileBuilder.process(await file.readAsString());
    }
}