import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { FOCUS_TOPICS, VERIFICATION_FOCUS_SKILLS, textSupportsFocus,
  textSupportsVerification } from '../supabase/functions/content-automation/focus.mjs';
import { planCandidates, topicResults } from '../supabase/functions/content-automation/planning.mjs';
import { discoverFallback } from '../supabase/functions/content-automation/discovery.mjs';

// Execute the real Edge handler with offline network/database/provider adapters.
// Type stripping requires Node 22.13+. No npm dependencies or real API calls.
let handler;
globalThis.Deno = { serve: fn => { handler = fn; }, env: { get: name => ({
  SUPABASE_URL: 'https://fixture.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture',
  GROQ_API_KEY: 'fixture', GROQ_MODEL: 'fixture-model',
})[name] } };
let service;
let feedItems = [];
globalThis.__generationClient = () => service;
globalThis.__generationParser = class { parse() { return { rss: { channel: { item: feedItems } } }; } };
let source = readFileSync(new URL('../supabase/functions/content-automation/index.ts', import.meta.url), 'utf8');
source = source.replace(/import \{ createClient \}[^;]+;/,
  'const createClient = globalThis.__generationClient;')
  .replace(/import \{ XMLParser \}[^;]+;/, 'const XMLParser = globalThis.__generationParser;')
  .replace(/from '\.\/(\w+\.mjs)'/g, (_, file) =>
    `from '${new URL(`../supabase/functions/content-automation/${file}`, import.meta.url).href}'`);
await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source)).toString('base64')}`);

const learningSignals = ['clear prompts', 'audience context', 'output formats', 'AI privacy', 'AI fact checking'];
const verifySignals = ['AI source credibility', 'AI claim fact checking', 'AI media provenance',
  'AI deepfake manipulation', 'AI citation references', 'AI uncertain evidence'];
const body = signal => `${signal}. ${'Educational AI source material with practical examples. '.repeat(25)}`;
const trusted = { id: 'source-id', name: 'Fixture publisher', source_url: 'https://trusted.invalid/',
  feed_url: 'https://trusted.invalid/feed', source_type: 'rss', relevance_keywords: ['AI'], trust_level: 5 };
function lesson(topic) {
  const signal = learningSignals[FOCUS_TOPICS.indexOf(topic)];
  return { title: `Learn ${signal}`, summary: `Practice ${signal}`, topic_id: topic, target_level: 2,
    objectives: Array.from({length: 4}, (_, i) => ({title: `Objective ${i}`, description: signal})),
    lesson_sections: Array.from({length: 6}, (_, i) => `Concept ${i}\n${`${signal} `.repeat(125)}`),
    questions: Array.from({length: 5}, (_, i) => ({question_type: 'scenario', stem: `Apply ${signal} ${i}`,
      options: ['A', 'B', 'C', 'D'], correct_index: 1, explanation: signal, difficulty: 2})),
    verification_case: null };
}
function verification(skill) {
  return { title: `Check ${skill}`, summary: 'Check the source-grounded AI scenario.',
    subskill: skill, case_type: 'claim', difficulty: 2, scenario: 'Check this AI claim.',
    claim_text: 'The source says this.', media_type: 'text', media_description: 'Source excerpt',
    evidence: Array.from({length: 4}, (_, i) => ({code: `e${i}`, label: 'Source', detail: 'Supplied source material', is_key: i < 2})),
    actions: Array.from({length: 4}, (_, i) => ({code: `a${i}`, label: 'Check', description: 'Read the source',
      useful: i < 2, reveals_evidence_codes: i < 2 ? [`e${i}`] : []})),
    source_options: ['A','B','C','D'], best_source_index: 1, correct_decision: 'insufficient_evidence',
    expected_confidence: 'low', explanation: 'The supplied evidence does not establish the claim.',
    learning_point: 'Check independent evidence.' };
}

function harness({ topics = FOCUS_TOPICS, verify = false, cap = 10, failTopic,
  missing = false, fallback = false, duplicate = false, invalid = false, saveFails = false,
  httpStatus, timeout = false, wrongBody = false, missingTopic, brokenFeed = false,
  omitSelection = false, cooldownMinutes = 30, lastManualRunAt = null, firstModelTimeout = false, advanceAfterFirstDraft = false, articleSaveFails = false,
  modelIds = ['fixture-model'], rateLimitedModels = [] } = {}) {
  const all = verify ? VERIFICATION_FOCUS_SKILLS : FOCUS_TOPICS;
  const signals = verify ? verifySignals : learningSignals;
  const rows = missing ? [] : topics.filter(topic => topic !== missingTopic).map(topic => {
    const i = all.indexOf(topic);
    return { id: `article-${i}`, title: signals[i], summary: body(signals[i]),
      source_url: `https://trusted.invalid/article-${i}`, ai_relevance_score: 8,
      content_excerpt: wrongBody ? '' : body(signals[i]), source_name: 'Fixture publisher', relevance_score: 80 };
  });
  feedItems = fallback ? [] : rows.map(row => ({ title: row.title, description: row.summary, link: row.source_url }));
  const inserts = [], calls = [], updates = [], modelCalls = [];
  const settings = { manual_cooldown_minutes: cooldownMinutes, last_manual_run_at: lastManualRunAt, enabled: true, max_articles_per_run: cap, max_drafts_per_day: 50,
    monthly_draft_cap: 100, max_drafts_per_run: cap, monthly_groq_request_cap: 100, focus_topics: topics };
  class Query {
    constructor(table) { this.table = table; this.kind = 'read'; }
    select(_, options) { this.head = options?.head; return this; }
    eq() { return this; } neq() { return this; } gte() { return this; }
    order() { return this; } limit() { return this; } or() { return this; }
    insert(value) { this.kind = 'insert'; this.value = value; return this; }
    update(value) { this.kind = 'update'; this.value = value; return this; }
    single() { return this; } maybeSingle() { return this; }
    then(resolve, reject) {
      let result = { data: null, error: null, count: 0 };
      if (this.kind === 'insert') {
        const isDraft = ['generated_content_drafts','verification_case_drafts'].includes(this.table);
        if ((isDraft && saveFails) || (this.table === 'discovered_articles' && articleSaveFails)) result.error = {message: 'Fixture persistence failure'};
        else { inserts.push({table: this.table, value: this.value}); result.data = {id: `saved-${inserts.length}`}; }
      } else if (this.kind === 'update') updates.push({table: this.table, value: this.value});
      else if (!this.head) {
        if (this.table === 'profiles') result.data = {role: 'administrator'};
        if (this.table.endsWith('settings')) result.data = settings;
        if (this.table === 'content_sources') result.data = [trusted];
        if (this.table === 'awareness_articles') result.data = fallback ? [] : rows;
        if (this.table === 'verification_case_drafts') result.data = duplicate ? [{id:'duplicate'}] : [];
        if (this.table === 'discovered_articles') result.data = duplicate ? {id:'duplicate',status:'processed'} : null;
      }
      return Promise.resolve(result).then(resolve, reject);
    }
  }
  service = { from: table => new Query(table), auth: { getUser: async () => ({data:{user:{id:'admin'}}}) },
    rpc: async name => ({data: name === 'claim_content_automation_run' ? 'fixture-run' : null, error:null}) };
  let clockOffset = 0;
  globalThis.fetch = async (url, options) => {
    url = String(url);
    if (url.includes('/models')) return Response.json({data:modelIds.map(id=>({id}))});
    if (url.includes('/chat/completions')) {
      const prompt = JSON.parse(options.body).messages[1].content;
      const model = JSON.parse(options.body).model;
      modelCalls.push(model);
      if (firstModelTimeout && modelCalls.length === 1) throw Error('Fixture first-model timeout');
      if (rateLimitedModels.includes(model)) return new Response('Model rate limited', {status:429});
      const topic = prompt.match(/ADMIN-SELECTED (?:FOCUS AREA \(MANDATORY\)|SKILL \(MANDATORY\)):\s*(\w+)/)?.[1];
      calls.push(topic);
      if (timeout || topic === failTopic) throw Error('Fixture provider timeout');
      if (httpStatus) return new Response('Provider unavailable', {status:httpStatus});
      if (advanceAfterFirstDraft && calls.length === 1) clockOffset = 110_000;
      const payload = invalid ? {title:'Invalid'} : verify ? verification(topic) : lesson(topic);
      return Response.json({choices:[{message:{content:JSON.stringify(payload)}}]});
    }
    if (url.endsWith('/feed')) {
      if (brokenFeed) throw Error('Fixture feed timeout');
      return new Response('<rss/>');
    }
    if (fallback && url === trusted.source_url) return new Response(`<title>AI learning</title><main>${body(signals[all.indexOf(topics[0])])}</main>`);
    const row = rows.find(row => row.source_url === url);
    return new Response(row && !wrongBody ? `<article>${row.summary}</article>`
      : `<article>${body('AI general market news')}</article>`);
  };
  return { inserts, calls, updates, modelCalls, async run() {
    const realNow = Date.now;
    Date.now = () => realNow() + clockOffset;
    try {
    const response = await handler(new Request('https://fixture.invalid/function', { method:'POST',
      headers:{authorization:'Bearer fixture','content-type':'application/json'},
      body: JSON.stringify({mode:'manual', ...(verify ? {target:'verification',
        ...(!omitSelection ? {focus_skills:topics} : {})} : {focus_topics:topics})}) }));
    return { response, data: await response.json(), drafts: inserts.filter(item => item.table ===
      (verify ? 'verification_case_drafts' : 'generated_content_drafts')) };
    } finally { Date.now = realNow; }
  } };
}

for (const verify of [false, true]) {
  const topics = verify ? VERIFICATION_FOCUS_SKILLS : FOCUS_TOPICS;
  for (const topic of topics) test(`${verify ? 'Verify' : 'Learning'} real handler generates ${topic}`, async () => {
    const h = harness({verify,topics:[topic]});
    const {data,drafts} = await h.run();
    assert.equal(drafts.length,1,JSON.stringify(data)); assert.equal(data.success,true);
    assert.equal(drafts[0].value.status,'draft');
    assert.equal(data.topicResults[0].topic,topic);
    assert.equal(drafts[0].value.draft_payload[verify ? 'subskill' : 'topic_id'],topic);
  });
  for (const count of [2,3,topics.length]) test(`${verify ? 'Verify' : 'Learning'} handles ${count} selected topics`, async () => {
    const {data,drafts} = await harness({verify,topics:topics.slice(0,count)}).run();
    assert.equal(drafts.length,count); assert.equal(data.topicResults.length,count);
    assert.ok(data.topicResults.every(item => item.created === 1));
    assert.equal(new Set(drafts.map(item => item.value.source_url)).size,count);
  });
  test(`${verify ? 'Verify' : 'Learning'} never exceeds a two-draft cap; reports every topic`, async () => {
    const {data,drafts} = await harness({verify,topics,cap:2}).run();
    assert.equal(drafts.length,2); assert.equal(data.success,false); assert.equal(data.partial,true);
    assert.equal(data.topicResults.filter(item => item.status === 'deferred_by_limit').length,topics.length-2);
  });
  test(`${verify ? 'Verify' : 'Learning'} timeout on one topic preserves other drafts`, async () => {
    const {data,drafts} = await harness({verify,topics:topics.slice(0,2),failTopic:topics[0]}).run();
    assert.equal(drafts.length,1); assert.equal(data.partial,true);
    assert.equal(data.topicResults.find(item => item.topic === topics[0]).created,0);
  });
  for (const option of ['duplicate','missing','invalid','saveFails','timeout']) {
    test(`${verify ? 'Verify' : 'Learning'} ${option} cannot report generation success`, async () => {
      const h = harness({verify,topics:[topics[0]],[option]:true});
      const {data,drafts} = await h.run();
      assert.equal(drafts.length,0); assert.equal(data.success,false);
      assert.equal(data.topicResults.length,1);
      if (option === 'duplicate' || option === 'missing') assert.equal(h.calls.length,0);
    });
  }
  test(`${verify ? 'Verify' : 'Learning'} trusted page fallback works after empty primary discovery`, async () => {
    const {data,drafts} = await harness({verify,topics:[topics[1]],fallback:true}).run();
    assert.equal(drafts.length,1); assert.equal(data.success,true);
  });
  test(`${verify ? 'Verify' : 'Learning'} rate limit is bounded and reported`, async () => {
    const h = harness({verify,topics:[topics[0]],httpStatus:429});
    const {data,drafts} = await h.run();
    assert.equal(drafts.length,0); assert.equal(data.success,false); assert.ok(h.calls.length <= 3);
  });
  test(`${verify ? 'Verify' : 'Learning'} no source for one topic does not discard the other`, async () => {
    const {data,drafts} = await harness({verify,topics:topics.slice(0,2),missingTopic:topics[0]}).run();
    assert.equal(drafts.length,1); assert.equal(data.partial,true);
    assert.equal(data.topicResults.find(item=>item.topic===topics[0]).status,'no_matching_sources');
  });
}

for (const verify of [false,true]) test(`${verify ? 'Verify' : 'Learning'} headline match with unrelated body cannot consume AI calls`, async () => {
  const h = harness({verify,topics:verify ? ['citation_verification'] : ['context'],wrongBody:true});
  const {data,drafts} = await h.run();
  assert.equal(drafts.length,0); assert.equal(h.calls.length,0); assert.equal(data.success,false);
});

test('legacy Verify callers without a picker retain automatic relevant skill selection', async () => {
  const {data,drafts} = await harness({verify:true,topics:VERIFICATION_FOCUS_SKILLS,cap:2,omitSelection:true}).run();
  assert.equal(drafts.length,2); assert.equal(data.success,true);
});

test('trusted page fallback recovers a broken feed without discarding its saved draft', async () => {
  const {data,drafts} = await harness({topics:['context'],fallback:true,brokenFeed:true}).run();
  assert.equal(drafts.length,1); assert.equal(data.partial,true);
});

test('canonical URLs and syndicated headlines cannot occupy multiple topic slots', () => {
  const candidates = [
    {url:'https://fixture.invalid/a?utm_source=test',title:'Audience context guide'},
    {url:'https://fixture.invalid/a#section',title:'More audience context'},
    {url:'https://fixture.invalid/b',title:'Audience context guide!'},
  ];
  assert.equal(planCandidates(candidates,['context'],textSupportsFocus).length,1);
});

test('objective migration only replaces the generated approval mapping and is guarded', () => {
  const sql = readFileSync(new URL('../supabase/migrations/20261019120000_generated_objective_mapping.sql',import.meta.url),'utf8');
  assert.match(sql,/publish_generated_content_draft\(uuid\)/);
  assert.match(sql,/jsonb_array_length\(v_draft.draft_payload->''objectives''\) - 1/);
  assert.match(sql,/Unexpected generated lesson objective mapping/);
  assert.doesNotMatch(sql,/update public\./i);
  // Five generated questions now reach all four objectives; the final one
  // remains on the last objective, matching the previous clamping contract.
  assert.deepEqual([1,2,3,4,5].map(index=>Math.max(0,Math.min(index-1,4-1))),[0,1,2,3,3]);
});

test('fair allocation rotates when capacity is smaller than the selection', () => {
  const candidates = FOCUS_TOPICS.map((topic,i) => ({url:`https://fixture/${i}`,title:learningSignals[i]}));
  assert.equal(new Set(FOCUS_TOPICS.map((_,seed) =>
    planCandidates(candidates,FOCUS_TOPICS,textSupportsFocus,seed)[0].focusTopic)).size,5);
  assert.equal(textSupportsVerification('AI privacy rules','media_provenance'),false);
  assert.equal(topicResults(['context'],[],{},{} )[0].status,'no_matching_sources');
});

for (const verify of [false,true]) test(`${verify ? 'Verify' : 'Learning'} never retries the rate-limited model per article or uses Orpheus`,async()=>{
  const h=harness({verify,topics:verify ? VERIFICATION_FOCUS_SKILLS.slice(0,2) : FOCUS_TOPICS.slice(0,2),
    modelIds:['llama-3.1-8b-instant','llama-3.3-70b-versatile','canopylabs/orpheus-v1-english'],
    rateLimitedModels:['llama-3.1-8b-instant']});
  const {drafts}=await h.run();assert.equal(drafts.length,2);
  assert.equal(h.modelCalls.filter(id=>id==='llama-3.1-8b-instant').length,1);
  assert.ok(!h.modelCalls.some(id=>id.includes('orpheus')));
});

test('fallback rejects unrelated pages, isolates provider failure and follows only real same-host links', async () => {
  const urls=[], failures=[];
  const found = await discoverFallback({sources:[trusted,{...trusted,source_url:'https://broken.invalid/'}],
    topics:['context'],supports:textSupportsFocus,aiEligible:text=>text.includes('AI'),
    clean: html=>html.replace(/<[^>]*>/g,' '),
    load: async url=> {
      urls.push(url); if(url.includes('broken')) throw Error('HTTP 429');
      if(url.endsWith('/context')) return body('AI audience context');
      return '<title>AI news</title><a href="https://evil.invalid/context">Audience context</a><a href="/context">Audience context</a>';
    }, onFailure: source=>failures.push(source.source_url) });
  assert.equal(found.length,1); assert.equal(found[0].url,'https://trusted.invalid/context');
  assert.ok(!urls.some(url=>url.includes('evil'))); assert.equal(failures.length,1);
});

for (const cooldownMinutes of [0, 2, 30]) {
  test('Learning real handler honors saved cooldown ' + cooldownMinutes, async () => {
    const h = harness({ topics: ['context'], cooldownMinutes, lastManualRunAt: new Date().toISOString() });
    const first = await h.run();
    if (cooldownMinutes === 0) {
      assert.equal(first.response.status, 200);
      assert.equal(first.drafts.length, 1);
      const second = await h.run();
      assert.equal(second.response.status, 200);
      assert.equal(h.calls.length, 2);
    } else {
      assert.equal(first.response.status, 429);
      assert.match(first.data.error, /cooldown/);
      assert.equal(h.calls.length, 0);
    }
  });
}
test('Learning retries another text model after a transport timeout', async () => {
  const h = harness({topics:['context'], firstModelTimeout:true, modelIds:['fixture-model','llama-3.3-70b-versatile']});
  const {data,drafts} = await h.run();
  assert.equal(drafts.length, 1, JSON.stringify(data));
  assert.equal(h.modelCalls.length, 2);
});
test('Learning failure response includes the actual provider cause', async () => {
  const {data} = await harness({topics:['context'], timeout:true}).run();
  assert.match(data.error, /Fixture provider timeout/);
});

test('Learning time budget stops further requests and preserves a saved draft', async () => {
  const h = harness({topics:['context','specificity'], advanceAfterFirstDraft:true});
  const {data,drafts} = await h.run();
  assert.equal(drafts.length,1);
  assert.equal(h.calls.length,1);
  assert.equal(data.partial,true);
  assert.equal(data.topicResults.filter(t=>t.created===0).length,1);
});
test('Learning article persistence errors produce a diagnostic response', async () => {
  const h = harness({topics:['context'], articleSaveFails:true});
  const {data,drafts} = await h.run();
  assert.equal(drafts.length,0);
  assert.match(data.error,/Fixture persistence failure/);
  assert.equal(data.processingFailures,1);
});
