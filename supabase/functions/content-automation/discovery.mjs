// Bounded fallback on administrator-enabled source URLs only. No invented URLs
// or search-provider dependency. A topic match is rechecked on fetched content.
export async function discoverFallback({ sources, topics, supports, load,
  clean, aiEligible, onFailure = (_source, _error) => {} }) {
  const found = [];
  const roots = sources.slice(0, 4);
  for (let index = 0; index < roots.length; index += 2) {
    await Promise.all(roots.slice(index, index + 2).map(async source => {
      try {
        const html = await load(source.source_url);
        const title = clean(html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ?? source.name);
        const body = clean(html);
        const matches = text => aiEligible(text) && topics.some(topic => supports(text, topic));
        const add = (url, label, text) => {
          if (text.length >= 300 && matches(text)) found.push({
            sourceId: source.id, sourceName: source.name, url, title: label,
            summary: text, publishedAt: null, relevanceScore: 50, topicHint: null,
          });
        };
        add(source.source_url, title, body);
        // One additional topical link per root, using only an actual href on
        // the configured host. A failed root cannot abort other providers.
        const anchors = [...html.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)];
        for (const anchor of anchors) {
          const label = clean(anchor[2]);
          if (!topics.some(topic => supports(label, topic))) continue;
          let url;
          try { url = new URL(anchor[1], source.source_url); } catch { continue; }
          const host = new URL(source.source_url).hostname;
          if (url.protocol !== 'https:' || url.hostname !== host ||
              url.href === source.source_url) continue;
          const text = clean(await load(url.href));
          add(url.href, label, text);
          break;
        }
      } catch (error) { onFailure(source, error); }
    }));
  }
  return found;
}
