// A corrected copy of `package:highlight`'s `xml` grammar (highlight 0.7.0),
// which is what `.html`, `.xml`, `.svg`, `.csproj`, `.cshtml` and friends are
// coloured with.
//
// Two deviations, both needed for a real HTML page to colour at all. The rest
// of the grammar is the upstream one, unchanged.
//
// 1. `<script>` and `<style>` open with `<script\b` / `<style\b`, not
//    `<script(?=\s|>)` / `<style(?=\s|>)`.
//
//    `highlight` finds the next lexeme by matching a mode's own combined
//    terminators against the source, then decides *which* mode matched by
//    re-testing each candidate `begin` against just that lexeme. A trailing
//    lookahead has nothing to look at once the source has been cut: the lexeme
//    for `<script>` is the six characters `<script`, so `(?=\s|>)` fails, the
//    script mode is skipped, and the generic `<tag` mode - which has no
//    `starts` - takes the tag instead. The `<script>` body is then read as
//    HTML markup, where a `<` in `for (let i = 0; i <= n; i++)` opens a tag and
//    the next `<` is *illegal*, which makes the parser give up on the whole
//    document: nothing coloured at all. A `\b` is satisfied at the end of the
//    lexeme, so the mode is chosen and the body reaches its `starts`.
//
// 2. A `<script>` body is JavaScript and a `<style>` body is CSS, so each is
//    handed to that one grammar rather than a list to guess among.
//
//    Guessing is what the multi-language list does: it parses the body with
//    every candidate and keeps the most relevant. `actionscript` and
//    `handlebars` are not registered here (this app keeps its language set
//    small on purpose - see `code_highlight.dart`), and a page whose script
//    happens to score better as `xml` than as `javascript` gets its code
//    coloured as markup. Naming the one language that can appear in a `<script>`
//    or `<style>` tag removes the guess, and the cost of trying four grammars
//    per block with it.
//
// The failure these fix is not a corner case: every page in this repo with a
// comparison in a script - `i <= n`, `a < b` - arrived uncoloured, while pages
// without one looked fine, which is what "HTML colouring works sometimes"
// looked like from the phone.

import 'package:highlight/highlight_core.dart' show Mode;

/// The two shared fragments `xml` borrows from `highlight`'s common modes,
/// written out here rather than imported: they live in `package:highlight/src/`
/// (not a public library), and `compileMode` mutates the modes it compiles, so
/// a fragment shared with every other grammar is one more way for an unrelated
/// language to change how HTML looks.
final _backslashEscape = Mode(begin: "\\\\[\\s\\S]", relevance: 0);
final _phrasalWords = Mode(
    begin:
        "\\b(a|an|the|are|I'm|isn't|don't|doesn't|won't|but|just|should|pretty|simply|enough|gonna|going|wtf|so|such|will|you|your|they|like|more)\\b");

final xml = Mode(
    refs: {
      '~contains~6~contains~0':
          Mode(endsWithParent: true, illegal: "<", relevance: 0, contains: [
        Mode(className: "attr", begin: "[A-Za-z0-9\\._:-]+", relevance: 0),
        Mode(begin: "=\\s*", relevance: 0, contains: [
          Mode(className: "string", endsParent: true, variants: [
            Mode(begin: "\"", end: "\"", contains: [Mode(ref: '~contains~3')]),
            Mode(begin: "'", end: "'", contains: [Mode(ref: '~contains~3')]),
            Mode(begin: "[^\\s\"'=<>`]+")
          ])
        ])
      ]),
      '~contains~3':
          Mode(className: "symbol", begin: "&[a-z]+;|&#[0-9]+;|&#x[a-f0-9]+;"),
      '~contains~0~contains~3': Mode(
          begin: "\\(",
          contains: [Mode(ref: '~contains~0~contains~0~contains~0')],
          end: "\\)"),
      '~contains~0~contains~2': Mode(
          className: "meta-string",
          begin: "'",
          end: "'",
          illegal: "\\n",
          contains: [_backslashEscape]),
      '~contains~0~contains~1': Mode(
          className: "meta-string",
          begin: "\"",
          end: "\"",
          illegal: "\\n",
          contains: [_backslashEscape]),
      '~contains~0~contains~0~contains~0': Mode(
          className: "meta-keyword",
          begin: "#?[a-z_][a-z1-9_-]+",
          illegal: "\\n"),
      '~contains~0~contains~0': Mode(
          begin: "\\s",
          contains: [Mode(ref: '~contains~0~contains~0~contains~0')]),
    },
    aliases: [
      "html",
      "xhtml",
      "rss",
      "atom",
      "xjb",
      "xsd",
      "xsl",
      "plist",
      "wsf",
      "svg"
    ],
    case_insensitive: true,
    contains: [
      Mode(
          className: "meta",
          begin: "<![a-z]",
          end: ">",
          relevance: 10,
          contains: [
            Mode(ref: '~contains~0~contains~0'),
            Mode(ref: '~contains~0~contains~1'),
            Mode(ref: '~contains~0~contains~2'),
            Mode(ref: '~contains~0~contains~3'),
            Mode(begin: "\\[", end: "\\]", contains: [
              Mode(className: "meta", begin: "<![a-z]", end: ">", contains: [
                Mode(ref: '~contains~0~contains~0'),
                Mode(ref: '~contains~0~contains~3'),
                Mode(ref: '~contains~0~contains~1'),
                Mode(ref: '~contains~0~contains~2')
              ])
            ])
          ]),
      Mode(
          className: "comment",
          begin: "<!--",
          end: "-->",
          contains: [
            _phrasalWords,
            Mode(
                className: "doctag",
                begin: "(?:TODO|FIXME|NOTE|BUG|XXX):",
                relevance: 0)
          ],
          relevance: 10),
      Mode(begin: "<\\!\\[CDATA\\[", end: "\\]\\]>", relevance: 10),
      Mode(ref: '~contains~3'),
      Mode(className: "meta", begin: "<\\?xml", end: "\\?>", relevance: 10),
      Mode(begin: "<\\?(php)?", end: "\\?>", subLanguage: [
        "php"
      ], contains: [
        Mode(begin: "/\\*", end: "\\*/", skip: true),
        Mode(begin: "b\"", end: "\"", skip: true),
        Mode(begin: "b'", end: "'", skip: true),
        Mode(
            className: null,
            begin: "'",
            end: "'",
            illegal: null,
            contains: null,
            skip: true),
        Mode(
            className: null,
            begin: "\"",
            end: "\"",
            illegal: null,
            contains: null,
            skip: true)
      ]),
      Mode(
          className: "tag",
          begin: "<style\\b",
          end: ">",
          keywords: {"name": "style"},
          contains: [Mode(ref: '~contains~6~contains~0')],
          starts: Mode(end: "</style>", returnEnd: true, subLanguage: ["css"])),
      Mode(
          className: "tag",
          begin: "<script\\b",
          end: ">",
          keywords: {"name": "script"},
          contains: [Mode(ref: '~contains~6~contains~0')],
          starts: Mode(
              end: "</script>", returnEnd: true, subLanguage: ["javascript"])),
      Mode(className: "tag", begin: "</?", end: "/?>", contains: [
        Mode(className: "name", begin: "[^\\/><\\s]+", relevance: 0),
        Mode(ref: '~contains~6~contains~0')
      ])
    ]);
