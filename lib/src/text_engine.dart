import "dart:async";

import "package:CommonLib/Collection.dart";
import "package:CommonLib/Logging.dart";
import "package:CommonLib/Random.dart";

import "text_engine_web.dart" if (dart.library.io) "text_engine_vm.dart" as Implementation;

/*
    TODO:
    - switching from recursive to iterative, with iteration limit
 */

String _escapedMapping(Match m) => m.group(0)!;
List<String> escapedSplit(String input, RegExp pattern) => pattern.allMatches(input).map(_escapedMapping).toList();

abstract class TextEngine {
    static const String defaultWordListPath = "wordlists";
    String wordListPath = defaultWordListPath;

    static const String delimiter = "#";
    static const String separator = "|";
    static const String selectionSeparator = "@";
    static const String includeSymbol = "@";
    static const String fileSeparator = ":";
    static const String defaultSymbol = "?";

    static final RegExp delimiterPattern = new RegExp("([^\\\\$delimiter]|\\\\$delimiter)+");
    static final RegExp separatorPattern = new RegExp("([^\\\\$separator]|\\\\$separator)+");
    static final RegExp sectionSeparatorPattern = new RegExp("([^\\\\$selectionSeparator]|\\\\$selectionSeparator)+");
    static final RegExp fileSeparatorPattern = new RegExp("([^\\\\$fileSeparator]|\\\\$fileSeparator)+");

    static final Logger _logger = new Logger("TextEngine");//, true);

    static RegExp mainPattern = new RegExp("$delimiter(.*?)$delimiter");
    static RegExp referencePattern = new RegExp("\\?(.*?)\\?");
    static RegExp escapePattern = new RegExp("\\\\(?!\\\\)");

    final Set<String> _loadedFiles = <String>{};
    Map<String, WordList> sourceWordLists = <String, WordList>{};
    Map<String, WordList> wordLists = <String, WordList>{};

    bool _processed = false;
    Random? rand;

    factory TextEngine([int? seed, String wordListPath = defaultWordListPath]) {
        return new Implementation.TextEngine.create(seed, wordListPath);
    }

    TextEngine.create([int? seed, String this.wordListPath = defaultWordListPath]) {
        this.rand = new Random(seed);
    }

    void setSeed(int seed) {
        this.rand = new Random(seed);
    }

    String? phrase(String rootList, {String? variant, TextStory? story}) {
        if (!_processed) {
            this.processLists();
        }

        rand ??= new Random();
        story ??= new TextStory();

        final Word? rootWord = _getWord(rootList);

        if (rootWord == null) {
            _logger.debug("Root list '$rootList' not found");
            return "[$rootList]";
        }

        return _process(rootWord.get(variant), story.variables);
    }

    Future<WordListFile> loadListFile(String path);

    Future<void> loadList(String key) async {
        if (_loadedFiles.contains(key)) {
            _logger.debug("World list '$key' already loaded, skipping");
            return;
        }

        _loadedFiles.add(key);

        final WordListFile file = await loadListFile("$wordListPath/$key.words");

        for (final String include in file.includes) {
            await loadList(include);
        }

        //sourceWordLists.addAll(file.lists);

        // let's get a little more nuanced for merging lists together
        for (final String name in file.lists.keys) {
            final WordList list = file.lists[name]!;

            if(sourceWordLists.containsKey(name)) {
                final WordList originalList = sourceWordLists[name]!;

                // copy in the new words
                for (final WeightPair<Word> pair in list.pairs) {
                    originalList.add(new Word.copy(pair.item), pair.weight);
                }

                // includes add weights if they already exist
                for (final String key in list.includes.keys) {
                    if (originalList.includes.containsKey(key)) {
                        originalList.includes[key] = originalList.includes[key]! + list.includes[key]!;
                    } else {
                        originalList.includes[key] = list.includes[key]!;
                    }
                }

                // defaults just override, but don't clear existing entries not in the new list
                for (final String key in list.defaults.keys) {
                    originalList.defaults[key] = list.defaults[key]!;
                }
            } else {
                sourceWordLists[name] = new WordList.copy(list);
            }
        }

        _processed = false;
    }

    void processLists() {
        _logger.debug("Processing word lists");
        this._processed = true;
        this.wordLists.clear();

        for (final String key in this.sourceWordLists.keys) {
            final WordList list = new WordList.copy(this.sourceWordLists[key]!);
            this.wordLists[key] = list;

            for (final String dkey in list.defaults.keys) {
                for (final Word w in list) {
                    if (!w._variants.containsKey(dkey)) {
                        w.addVariant(dkey, list.defaults[dkey]!);
                    }
                }
            }
        }

        for (final String key in this.wordLists.keys) {
            final WordList list = this.wordLists[key]!;

            list.processIncludes(this.wordLists);

            for (final Word word in list) {

                // add default variants
                for (final String dkey in list.defaults.keys) {
                    if (!word._variants.containsKey(dkey)) {
                        word._variants[dkey] = list.defaults[dkey]!;
                    }
                }

                // resolve references
                for (final String vkey in word._variants.keys) {
                    word._variants[vkey] = word._variants[vkey]!.replaceAllMapped(referencePattern, (Match match) {
                        final String variant = match.group(1)!;
                        if (!word._variants.containsKey(variant)) {
                            return "[$variant]";
                        }
                        return word._variants[variant]!;
                    });
                }
            }
        }
    }

    Word? _getWord(String list) {
        if (!wordLists.containsKey(list)) {
            _logger.debug("List '$list' not found");
            return null;
        }

        final WordList words = wordLists[list]!;

        return rand!.pickFrom(words);
    }

    String? _process(String? input, Map<String,Word> savedWords) {
        if (input == null) { return null; }

        input = input.replaceAllMapped(mainPattern, (Match match) {
            final String raw = match.group(1)!;
            final List<String> sections = escapedSplit(raw, separatorPattern);//raw.split(SEPARATOR);

            Word? outword;
            String? variant;

            // main section
            {
                final List<String> parts = sections[0].split(selectionSeparator);

                if (parts.length > 1) {
                    variant = parts[1];
                }

                final Word? w = _getWord(parts[0]);

                outword = w;
            }

            if (sections.length > 1) {
                for (int i=1; i<sections.length; i++) {
                    final String section = sections[i];

                    final List<String> parts = section.split(selectionSeparator);

                    final String tag = parts[0];

                    if(tag == "var") { // read or write a variable

                        if (parts.length < 2) { continue; }
                        final String variable = parts[1];

                        if (savedWords.containsKey(variable)) {
                            outword = savedWords[variable];
                        } else {
                            savedWords[variable] = outword!;
                        }

                    }
                }
            }

            if (outword == null) {
                return "[${sections[0]}]";
            }
            String? output = outword.get(variant);

            if (output == null) {
                _logger.debug("Missing variant '$variant' for word '$outword', falling back to base");
                output = outword.get();
            }

            return _process(output, savedWords) ?? "";
        });

        return input;
    }
}

class Word {
    static const String baseName = "MAIN";
    late Map<String,String> _variants;

    Word(String word, [Map<String,String>? variants]) {
        _variants = variants ?? <String,String>{};
        _variants[baseName] = word;
    }

    factory Word.copy(Word other) => new Word(other.get()!, new Map<String,String>.from(other._variants));

    String? get([String? variant]) {
        variant ??= baseName;
        if (_variants.containsKey(variant)) {
            return _variants[variant]!;
        }
        return null;
    }

    void addVariant(String key, String variant) {
        _variants[key] = variant;
    }

    @override
    String toString() => "[Word: ${get()}]";
}

class WordList extends WeightedList<Word> {
    Map<String, double> includes = <String, double>{};
    Map<String, String> defaults = <String, String>{};

    final String name;
    bool _processed = false;

    WordList(String this.name) : super();

    factory WordList.copy(WordList other) {
        final WordList copy = new WordList(other.name);

        for (final String key in other.includes.keys) {
            copy.includes[key] = other.includes[key]!;
        }

        for (final String key in other.defaults.keys) {
            copy.defaults[key] = other.defaults[key]!;
        }

        for (final WeightPair<Word> pair in other.pairs) {
            copy.addPair(new WeightPair<Word>(new Word.copy(pair.item), pair.weight));
        }

        return copy;
    }

    @override
    String toString() => "WordList '$name': ${super.toString()}";

    void processIncludes(Map<String, WordList> wordlists, [Set<WordList>? visited]) {
        if (_processed) { return; }
        _processed = true;

        final Set<WordList> visited = <WordList>{};
        visited.add(this);

        for (final String key in this.includes.keys) {
            if (wordlists.containsKey(key)) {
                final WordList list = wordlists[key]!;

                if (visited.contains(list)) {
                    TextEngine._logger.warn("Include loop detected in list '$name', already visited '${list.name}', ignoring");
                    continue;
                }

                list.processIncludes(wordlists, visited);
            }
        }

        for (final String key in includes.keys) {
            if (!wordlists.containsKey(key)) { continue; }
            final WordList list = wordlists[key]!;
            for (final WeightPair<Word> pair in list.pairs) {
                this.add(pair.item, pair.weight * includes[key]!);
            }
        }
    }
}

class WordListFile {
    List<String> includes = <String>[];
    Map<String,WordList> lists = <String,WordList>{};

    WordListFile();

    @override
    String toString() => "[WordListFile: $lists ]";
}

class TextStory {
    Map<String,Word> variables = <String,Word>{};

    operator []=(String name, Word value) => variables[name] = value;
    void setString(String name, String value) => variables[name] = new Word(value);

    Word? operator [](String name) => variables[name];
    String? getString(String name) => variables[name]?.get();
}