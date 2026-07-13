/// Result of [splitLeadingTitle]: the detected [title] and the remaining
/// [body] text.
typedef TitleSplit = ({String title, String body});

/// Sentence-ending punctuation that makes a line look like prose rather than
/// a title.
final _sentenceEnd = RegExp(r'[.!?,;:]$');

/// Attempts to split [text] into a leading title line and the body text.
///
/// Returns `null` when the first non-empty line does not look like a title.
/// A line looks like a title when it is at most [maxLength] characters and
/// [maxWords] words, there is body text after it, and it either does not end
/// with sentence punctuation or is separated from the body by a blank line
/// (a visual gap marks a heading regardless of punctuation).
TitleSplit? splitLeadingTitle(
  String text, {
  int maxLength = 80,
  int maxWords = 12,
}) {
  final lines = text.split('\n');

  var first = 0;
  while (first < lines.length && lines[first].trim().isEmpty) {
    first++;
  }
  if (first >= lines.length) return null;

  final title = lines[first].trim();
  final body = lines.skip(first + 1).join('\n').trim();
  if (body.isEmpty) return null;

  if (title.length > maxLength) return null;
  if (title.split(RegExp(r'\s+')).length > maxWords) return null;

  final blankLineAfter =
      first + 1 < lines.length && lines[first + 1].trim().isEmpty;
  if (_sentenceEnd.hasMatch(title) && !blankLineAfter) return null;

  return (title: title, body: body);
}
