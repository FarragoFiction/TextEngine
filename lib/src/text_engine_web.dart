import "package:LoaderLib/Loader.dart";

import "WordListFileFormat.dart";
import "text_engine.dart" as ParentInterface;

class TextEngine extends ParentInterface.TextEngine {
    static WordListFileFormat format = _initFormat();

    TextEngine.create([int seed, String wordListPath = ParentInterface.TextEngine.defaultWordListPath]) : super.create(seed, wordListPath);

    @override
    Future<ParentInterface.WordListFile> loadListFile(String path) {
        return Loader.getResource(path, format: format);
    }

    @override
    String phrase(String rootList, {String variant, ParentInterface.TextStory story}) {
        _initFormat();
        return super.phrase(rootList, variant:variant, story:story);
    }

    static bool _formatInitialised = false;
    static WordListFileFormat _initFormat() {
        if (_formatInitialised) { return null; }
        _formatInitialised = true;

        final WordListFileFormat format = new WordListFileFormat();
        Formats.addMapping(format, ".words");
        return format;
    }
}