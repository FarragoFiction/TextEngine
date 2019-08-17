import "dart:async";

import "package:LoaderLib/Loader.dart";

import "text_engine.dart";
import "wordlistfilebuilder.dart";

class WordListFileFormat extends StringFileFormat<WordListFile> {

    @override
    String mimeType() => "text/plain";

    @override
    Future<WordListFile> read(String input) async {
        return WordListFileBuilder.process(input);
    }

    @override
    Future<String> write(WordListFile data) => throw Exception("WordListFile write NYI");

    @override
    String header() => WordListFileBuilder.header;
}