// Shared by production orchestration and fixture tests. No network/AI calls.
function sourceKey(value) {
  try {
    const url = new URL(value);
    url.hash = '';
    for (const key of [...url.searchParams.keys()]) {
      if (key.startsWith('utm_')) url.searchParams.delete(key);
    }
    return url.href.replace(/\/$/, '');
  } catch { return value; }
}

export function planCandidates(candidates, topics, supports, seed = 0) {
  if (!topics.length) return [];
  const offset = Math.abs(seed) % topics.length;
  const order = [...topics.slice(offset), ...topics.slice(0, offset)];
  const pools = new Map(order.map(topic => [topic, candidates.filter(c =>
    supports(`${c.title ?? ''} ${c.summary ?? ''}`, topic))]));
  const used = new Set();
  const usedTitles = new Set();
  const titleKey = candidate => (candidate.title ?? '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const plan = [];
  let added;
  do {
    added = false;
    for (const topic of order) {
      // Prefer sources that have fewer alternative curricular uses.
      const candidate = pools.get(topic).filter(c => !used.has(sourceKey(c.url)) &&
        !usedTitles.has(titleKey(c))).sort((a, b) =>
        order.filter(t => pools.get(t).includes(a)).length -
        order.filter(t => pools.get(t).includes(b)).length)[0];
      if (!candidate) continue;
      used.add(sourceKey(candidate.url));
      // Syndicated copies can have different URLs but the same headline.
      if (titleKey(candidate)) usedTitles.add(titleKey(candidate));
      plan.push({ candidate, focusTopic: topic });
      added = true;
    }
  } while (added);
  return plan;
}

export function topicResults(topics, plan, saved, attempted) {
  return topics.map(topic => ({
    topic,
    created: saved[topic] ?? 0,
    status: (saved[topic] ?? 0) > 0 ? 'created'
      : !plan.some(entry => entry.focusTopic === topic) ? 'no_matching_sources'
      : (attempted[topic] ?? 0) > 0 ? 'no_new_valid_draft'
      : 'deferred_by_limit',
  }));
}

export function topicSummary(results) {
  return results.map(result => `${result.topic}: ${result.created > 0
    ? `${result.created} saved` : result.status.replaceAll('_', ' ')}`).join('; ');
}
