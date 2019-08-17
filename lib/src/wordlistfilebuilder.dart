import "package:CommonLib/Logging.dart";

import "text_engine.dart";

abstract class WordListFileBuilder {
    static const String header = "TextEngine Word List";
    static final RegExp _newline = new RegExp("[\n\r]+");
    static final RegExp _spaces = new RegExp("( *)(.*)");
    static final RegExp _comment_start = new RegExp("^\s*\/\/");
    static final RegExp _comment_split = new RegExp("\/\/");
    static final Logger _logger = new Logger("WordListFileBuilder");//, true);
    static const int _tab = 4;

    static WordListFile process(String input) {
        final List<String> lines = input.split(_newline);
        if (lines[0].trimRight() != header) {
            throw Exception("Invalid WordList file header: '${lines[0]}'");
        }

        final WordListFile file = new WordListFile();

        int lineNumber = 0;

        WordList currentList;
        Word currentWord;

        final Map<String, String> globalDefaults = <String, String>{};

        while (lineNumber + 1 < lines.length) {
            lineNumber++;
            String line = lines[lineNumber];
            _logger.debug("Reading line $lineNumber, raw: $line");
            line = line.split(_comment_split)[0];

            if (line.isEmpty) {
                _logger.debug("Empty line");
                continue;
            }
            if (line.startsWith(_comment_start)) {
                _logger.debug("Comment: $line");
                continue;
            }

            if (line.startsWith(TextEngine.includeSymbol)) {
                final String include = line.substring(1);
                _logger.debug("new file include: $include");
                file.includes.add(include);
            } else if (line.startsWith(TextEngine.defaultSymbol)) {
                final List<String> parts = escapedSplit(line.substring(1), TextEngine.fileSeparatorPattern);
                if (parts.length < 2) {
                    _logger.error("Invalid global default '$line'");
                } else {
                    final String def = parts[0];
                    final String val = parts[1];
                    _logger.debug("new global default '$def': '$val'");
                    globalDefaults[def] = val;
                }
            } else {
                final Match m = _spaces.matchAsPrefix(line);
                if (m != null) {
                    final int spaces = m
                        .group(1)
                        .length;
                    String content = line.substring(spaces);
                    if (content.isEmpty) {
                        continue;
                    }

                    if (spaces == 0) { // new wordlist

                        content = content.trimRight();
                        _logger.debug("new WordList: $content");
                        currentList = new WordList(content);
                        currentList.defaults.addAll(globalDefaults);
                        file.lists[content] = currentList;
                    } else if (spaces == _tab) { // a default or include or word

                        if (content.startsWith(TextEngine.defaultSymbol)) { // default

                            content = content.substring(1);
                            final List<String> parts = escapedSplit(content, TextEngine.fileSeparatorPattern);

                            _logger.debug("list default: $content");
                            if (parts.length < 2) {
                                _logger.error("Invalid list default '$line'");
                            } else if (currentList != null) {
                                final String def = _removeEscapes(parts[0]);
                                final String val = _removeEscapes(parts[1]);
                                _logger.debug("new list default for '${currentList.name}': '$def' -> '$val'");
                                currentList.defaults[def] = val;
                            }
                        } else if (content.startsWith(TextEngine.includeSymbol)) { // include

                            final String include = content.substring(1);
                            _logger.debug("list include: $include");
                            final List<String> parts = escapedSplit(content, TextEngine.fileSeparatorPattern);
                            double weight = 1.0;
                            if (parts.length > 1) {
                                weight = double.tryParse(parts[1]);
                                if (weight == null) {
                                    _logger.warn("Invalid include weight '${parts[1]}' for word '${parts[0]}' in list '${currentList.name}', using 1.0");
                                    weight = 1.0;
                                }
                            }
                            currentList.includes[_removeEscapes(include)] = weight;
                        } else { // word

                            _logger.debug("new Word: $content");
                            final List<String> parts = escapedSplit(line, TextEngine.fileSeparatorPattern);
                            double weight = 1.0;
                            if (parts.length > 1) {
                                weight = double.tryParse(parts[1]);
                                if (weight == null) {
                                    _logger.warn("Invalid weight '${parts[1]}' for word '${parts[0]}' in list '${currentList.name}', using 1.0");
                                    weight = 1.0;
                                }
                            }
                            currentWord = new Word(_removeEscapes(parts[0]).trim());
                            currentList.add(currentWord, weight);
                        }
                    } else if (spaces == _tab * 2) { // a variant

                        _logger.debug("new Variant: $content");
                        final List<String> parts = escapedSplit(line, TextEngine.fileSeparatorPattern);
                        if (parts.length != 2) {
                            _logger.error("Invalid variant for ${currentWord.get()} in ${currentList.name}");
                        } else {
                            currentWord.addVariant(_removeEscapes(parts[0]).trim(), _removeEscapes(_trimFirstSpace(parts[1])));
                        }
                    }
                }
            }
        }

        return file;
    }

    static String _trimFirstSpace(String input) {
        if (input.startsWith(" ")) {
            return input.substring(1);
        }
        return input;
    }

    static String _removeEscapes(String input) => input.replaceAll(TextEngine.escapePattern, "");
}