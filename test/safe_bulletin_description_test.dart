import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/utils/safe_bulletin_description.dart';

String plainText(List<BulletinDescriptionRun> runs) =>
    runs.map((run) => run.text).join();

void main() {
  group('parseBulletinDescription', () {
    test('preserves plain text and existing line breaks', () {
      final runs = parseBulletinDescription('Ordinary text\nSecond line');

      expect(runs, const [
        BulletinDescriptionRun('Ordinary text\nSecond line', bold: false),
      ]);
    });

    test('supports bold, strong, and nested bold formatting', () {
      final runs = parseBulletinDescription(
        'Before <b>bold <strong>and nested</strong></b> after',
      );

      expect(runs, const [
        BulletinDescriptionRun('Before ', bold: false),
        BulletinDescriptionRun('bold and nested', bold: true),
        BulletinDescriptionRun(' after', bold: false),
      ]);
    });

    test('supports italic, underline, and combined nested formatting', () {
      final runs = parseBulletinDescription(
        'Plain <b>bold <i>bold italic <u>all three</u></i></b> '
        '<em>italic</em> <u>underlined</u>',
      );

      expect(runs, const [
        BulletinDescriptionRun('Plain ', bold: false),
        BulletinDescriptionRun('bold ', bold: true),
        BulletinDescriptionRun('bold italic ', bold: true, italic: true),
        BulletinDescriptionRun(
          'all three',
          bold: true,
          italic: true,
          underline: true,
        ),
        BulletinDescriptionRun(' ', bold: false),
        BulletinDescriptionRun('italic', bold: false, italic: true),
        BulletinDescriptionRun(' ', bold: false),
        BulletinDescriptionRun('underlined', bold: false, underline: true),
      ]);
    });

    test('handles mismatched and unclosed inline tags predictably', () {
      final runs = parseBulletinDescription(
        '<b>bold <i>both</b> italic</i> plain </u><u>underlined',
      );

      expect(runs, const [
        BulletinDescriptionRun('bold ', bold: true),
        BulletinDescriptionRun('both', bold: true, italic: true),
        BulletinDescriptionRun(' italic', bold: false, italic: true),
        BulletinDescriptionRun(' plain ', bold: false),
        BulletinDescriptionRun('underlined', bold: false, underline: true),
      ]);
    });

    test('turns breaks and block boundaries into readable line breaks', () {
      final runs = parseBulletinDescription(
        '<p>First<br>Second</p><div>Third</div><p>Fourth</p>',
      );

      expect(plainText(runs), 'First\nSecond\n\nThird\n\nFourth');
    });

    test('renders ordered and unordered lists with stable spacing', () {
      final runs = parseBulletinDescription(
        '<p>Before</p><ol><li>First</li><li>Second</li></ol>'
        '<ul><li>Alpha</li><li>Beta</li></ul><p>After</p>',
      );

      expect(
        plainText(runs),
        'Before\n\n1. First\n2. Second\n• Alpha\n• Beta\n\nAfter',
      );
    });

    test(
      'supports nested lists with bounded indentation and counter resets',
      () {
        final deeplyNested =
            '${List.filled(9, '<ul>').join()}'
            '<li>Deep</li>'
            '${List.filled(9, '</ul>').join()}';
        final runs = parseBulletinDescription(
          '<ol><li>One<ul><li>Nested</li></ul></li><li>Two</li></ol>'
          '<ol><li>Reset</li></ol>$deeplyNested',
        );

        expect(
          plainText(runs),
          startsWith('1. One\n  • Nested\n2. Two\n1. Reset\n'),
        );
        expect(plainText(runs), endsWith('${'  ' * 6}• Deep'));
      },
    );

    test('decodes the supported named and numeric entities', () {
      final runs = parseBulletinDescription(
        '&lt;safe&gt; &amp; &quot;quoted&quot; &apos;ok&apos; '
        'A&#66;&#x43; &nbsp; &#x1F642; &copy;',
      );

      expect(plainText(runs), '<safe> & "quoted" \'ok\' ABC \u00a0 🙂 &copy;');
    });

    test('removes unsupported tags but keeps their ordinary text', () {
      final runs = parseBulletinDescription(
        '<mark>Highlighted becomes ordinary</mark> and '
        '<a title="1 > 0" href="https://example.test">link text</a>.'
        '<!doctype html>',
      );

      expect(plainText(runs), 'Highlighted becomes ordinary and link text.');
      expect(runs.every((run) => !run.bold), isTrue);
    });

    test('formats the observed Try Holiday 2 description safely', () {
      final runs = parseBulletinDescription(
        '<b>Lets try </b><i>this out </i><u>again:</u><br>'
        '<ol><li>Try one more time<br></li></ol>'
        '<div><ul><li>And another try</li></ul></div>',
      );

      expect(
        plainText(runs),
        'Lets try this out again:\n1. Try one more time\n• And another try',
      );
      expect(runs.any((run) => run.bold && run.text == 'Lets try '), isTrue);
      expect(runs.any((run) => run.italic && run.text == 'this out '), isTrue);
      expect(runs.any((run) => run.underline && run.text == 'again:'), isTrue);
      expect(plainText(runs), isNot(contains('<')));
    });

    test('discards unsafe elements and all of their contents', () {
      final runs = parseBulletinDescription(
        'Keep'
        '<script>alert(1)</script>'
        '<style>.bad{display:block}</style>'
        '<iframe>frame</iframe>'
        '<object>object</object>'
        '<embed src="remote">'
        '<template>template</template>'
        ' this',
      );

      expect(plainText(runs), 'Keep this');
    });

    test('fails closed for malformed and unclosed markup', () {
      expect(
        plainText(parseBulletinDescription('Start <b>bold to end')),
        'Start bold to end',
      );
      expect(
        plainText(
          parseBulletinDescription('Visible<script>hidden without a close'),
        ),
        'Visible',
      );
      expect(
        plainText(parseBulletinDescription('Visible <unknown unfinished')),
        'Visible ',
      );
      expect(
        plainText(parseBulletinDescription('Two is < three')),
        'Two is < three',
      );
    });

    test('replaces unsafe numeric scalar values', () {
      expect(plainText(parseBulletinDescription('A&#0;B&#xD800;C')), 'A�B�C');
    });
  });
}
