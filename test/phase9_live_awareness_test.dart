import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/awareness_article.dart';

void main() {
  group('Phase 9 live awareness model', () {
    test('maps a Philippines awareness article safely', () {
      final article = AwarenessArticle.fromMap({
        'id': 'a1',
        'title': 'New AI impersonation scam warning',
        'summary': 'A trusted source warns users about impersonation attempts.',
        'why_it_matters': 'Check official channels before sending money.',
        'source_name': 'Philippine News Agency',
        'source_domain': 'pna.gov.ph',
        'source_url': 'https://www.pna.gov.ph/articles/example',
        'image_url': 'https://example.com/image.jpg',
        'published_at': '2026-08-25T00:00:00Z',
        'category': 'scams',
        'region': 'Philippines',
        'relevance_score': 94,
        'trust_level': 100,
        'saved': true,
        'read': false,
      });

      expect(article.isPhilippines, isTrue);
      expect(article.category, AwarenessCategory.scams);
      expect(article.saved, isTrue);
      expect(article.read, isFalse);
      expect(article.sourceName, 'Philippine News Agency');
    });

    test('unknown categories fall back to online safety', () {
      final article = AwarenessArticle.fromMap({
        'id': 'a2',
        'title': 'Safety update',
        'source_name': 'Source',
        'source_domain': 'example.com',
        'source_url': 'https://example.com/story',
        'category': 'unknown',
      });

      expect(article.category, AwarenessCategory.onlineSafety);
    });
  });
}
