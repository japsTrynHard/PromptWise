import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/content_item.dart';

class ContentRepository {
  final SupabaseClient _client;

  const ContentRepository(this._client);

  Future<List<ContentItem>> fetchItems({
    required bool includeUnpublished,
  }) async {
    dynamic query = _client.from('content_items').select();
    if (!includeUnpublished) {
      query = query.eq('status', ContentStatus.published.databaseValue);
    }
    final response = await query
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);
    return _mapRows(response as List);
  }

  Stream<List<ContentItem>> watchVisibleItems() {
    return _client
        .from('content_items')
        .stream(primaryKey: const ['id'])
        .order('sort_order', ascending: true)
        .map(_mapRows);
  }

  Future<ContentItem> createItem(ContentItem item) async {
    final response = await _client
        .from('content_items')
        .insert(item.toDatabaseMap())
        .select()
        .single();
    return ContentItem.fromMap(Map<String, dynamic>.from(response));
  }

  Future<ContentItem> updateItem(ContentItem item) async {
    final response = await _client
        .from('content_items')
        .update(item.toDatabaseMap(includeId: false))
        .eq('id', item.id)
        .select()
        .single();
    return ContentItem.fromMap(Map<String, dynamic>.from(response));
  }

  Future<void> deleteItem(String id) async {
    await _client.from('content_items').delete().eq('id', id);
  }

  Future<List<ContentVersion>> fetchVersions(String contentId) async {
    final response = await _client
        .from('content_item_versions')
        .select()
        .eq('content_id', contentId)
        .order('version', ascending: false);
    return (response as List)
        .map(
          (row) =>
              ContentVersion.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  List<ContentItem> _mapRows(List<dynamic> rows) {
    return rows
        .map(
          (row) => ContentItem.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }
}
