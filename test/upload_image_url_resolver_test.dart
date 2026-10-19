import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/services/upload_image_url_resolver.dart';

void main() {
  group('UploadImageUrlResolver', () {
    final resolver = UploadImageUrlResolver(
      Uri.parse('https://hris.example.test:8443/api/v1?ignored=yes'),
    );

    test('resolves approved raster paths against the backend origin', () {
      expect(
        resolver.resolve('/uploads/1760000000000.jpg'),
        Uri.parse('https://hris.example.test:8443/uploads/1760000000000.jpg'),
      );
      expect(
        resolver.resolve('/uploads/1760000000000-image_name.WEBP'),
        Uri.parse(
          'https://hris.example.test:8443/uploads/'
          '1760000000000-image_name.WEBP',
        ),
      );
      for (final extension in ['jpeg', 'png', 'gif']) {
        expect(resolver.resolve('/uploads/image.$extension'), isNotNull);
      }
      final development = UploadImageUrlResolver(
        Uri.parse('http://10.0.2.2:5000'),
      );
      expect(
        development.resolve('/uploads/dev.png'),
        Uri.parse('http://10.0.2.2:5000/uploads/dev.png'),
      );
    });

    test('rejects external, protocol-relative and unsupported schemes', () {
      for (final value in [
        'https://external.example/image.jpg',
        '//external.example/image.jpg',
        'data:image/png;base64,AAAA',
        'file:///uploads/image.jpg',
        'content://uploads/image.jpg',
      ]) {
        expect(resolver.resolve(value), isNull, reason: value);
      }
    });

    test('rejects traversal, encoding, nesting and backslashes', () {
      for (final value in [
        '/uploads/../secret.jpg',
        '/uploads/image..jpg',
        '/uploads/%2e%2e/secret.jpg',
        '/uploads/image%2ejpg',
        '/uploads/folder/image.jpg',
        r'/uploads\image.jpg',
      ]) {
        expect(resolver.resolve(value), isNull, reason: value);
      }
    });

    test('rejects query, fragment, controls, bad types and long input', () {
      for (final value in <Object?>[
        '/uploads/image.jpg?token=value',
        '/uploads/image.jpg#part',
        '/uploads/image.jpg\n',
        ' /uploads/image.jpg',
        '/uploads/image.jpg ',
        '/uploads/image.svg',
        '/uploads/image.exe',
        '/uploads/.jpg',
        '/uploads/',
        '',
        42,
        null,
        '/uploads/${'a' * 290}.jpg',
      ]) {
        expect(resolver.resolve(value), isNull, reason: '$value');
      }
    });

    test('rejects invalid backend origins', () {
      expect(
        () => UploadImageUrlResolver(Uri.parse('file:///server')),
        throwsArgumentError,
      );
      expect(
        () => UploadImageUrlResolver(
          Uri.parse('https://user:secret@hris.example.test'),
        ),
        throwsArgumentError,
      );
    });
  });
}
