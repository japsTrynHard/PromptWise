// Optional test-only PostgreSQL runtime: npm install --prefix <temp-dir>
// --no-save @electric-sql/pglite; set PGLITE_MODULE to its dist/index.js.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
if (!process.env.PGLITE_MODULE) { test('PostgreSQL security tests (set PGLITE_MODULE to run)', {skip:true},()=>{}); } else {
const {PGlite} = await import(pathToFileURL(process.env.PGLITE_MODULE).href);
const db = new PGlite();
const root = new URL('../',import.meta.url);
const read = file => readFileSync(new URL(file,root),'utf8').replaceAll('\r\n','\n');
const schema = read('supabase/schema.sql');
const user = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const request = '33333333-3333-4333-8333-333333333333';
const sql = text => db.exec(text);
const scalar = async text => (await db.query(text)).rows[0]?.value;
const functionSql = name => {
  const start = schema.indexOf(`CREATE OR REPLACE FUNCTION "public"."${name}"(`);
  assert.ok(start>=0,name);
  return schema.slice(start,schema.indexOf('\n$$;',start)+4);
};
await sql(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);
INSERT INTO auth.users VALUES('${user}'),('${other}');
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$SELECT nullif(current_setting('test.uid',true),'')::uuid$$;
GRANT USAGE ON SCHEMA auth,public TO authenticated,service_role;
CREATE TYPE public.app_role AS ENUM('learner','administrator');
CREATE TYPE public.content_type AS ENUM('module','lesson','quiz','activity','awareness');
CREATE TYPE public.content_status AS ENUM('draft','published','archived');
CREATE FUNCTION public.phase9_is_admin() RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
CREATE FUNCTION public.rebuild_adaptive_mastery_for_user(uuid) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN; END$$;`);
const tables = ['profiles','content_items','assessment_attempts','question_attempts','prompt_coach_daily_usage',
 'verification_cases','verification_sessions','verification_session_cases','verification_case_attempts','verification_subskill_mastery','verification_case_exposure','topic_mastery'];
for(const table of tables) {
 const start = schema.indexOf(`CREATE TABLE IF NOT EXISTS "public"."${table}" (`);
 assert.ok(start>=0,table);
 await sql(schema.slice(start,schema.indexOf('\n);',start)+3));
}
// Apply the real primary/unique constraints and identities for these tables.
for(const statement of schema.matchAll(/ALTER TABLE(?: ONLY)? "public"\."(\w+)"[\s\S]*?;/g)) {
 if(!tables.includes(statement[1])) continue;
 if(/ADD CONSTRAINT[\s\S]*(PRIMARY KEY|UNIQUE)|ADD GENERATED/.test(statement[0]) && !/FOREIGN KEY/.test(statement[0])) await sql(statement[0]);
}
for(const name of ['prompt_coach_ai_usage_status','reserve_prompt_coach_ai_use','refund_prompt_coach_ai_use','record_adaptive_attempt','record_adaptive_diagnostic','submit_verification_guess','submit_verification_case_attempt']) await sql(functionSql(name));
await sql(read('supabase/migrations/20260901120000_quick_check_rotation.sql'));
await sql(`ALTER TABLE verification_cases ENABLE ROW LEVEL SECURITY; GRANT SELECT ON verification_cases TO authenticated;
GRANT EXECUTE ON FUNCTION refund_prompt_coach_ai_use() TO authenticated;
SELECT set_config('test.uid','${user}',false);`);
for(const file of ['20261019130000_secure_coach_refunds.sql','20261019131000_verification_answer_protection.sql','20261019132000_assessment_answer_validation.sql']) await sql(read(`supabase/migrations/${file}`));

test('learners cannot call either refund path or reserve a service request',async()=> {
 await sql('SET ROLE authenticated');
 for(const call of [`refund_prompt_coach_ai_use()`,`settle_prompt_coach_ai_request('${request}','${user}',false)`,`reserve_prompt_coach_ai_request('${request}','${user}')`]) await assert.rejects(sql(`SELECT ${call}`),/permission denied/);
 await sql('RESET ROLE');
});
test('backend failure refund is bound to its user/request and is idempotent',async()=> {
 await sql(`SELECT reserve_prompt_coach_ai_request('${request}','${user}')`);
 await assert.rejects(sql(`SELECT settle_prompt_coach_ai_request('${request}','${other}',false)`),/Unknown AI request/);
 assert.equal(await scalar(`SELECT settle_prompt_coach_ai_request('${request}','${user}',false) AS value`),true);
 assert.equal(await scalar(`SELECT settle_prompt_coach_ai_request('${request}','${user}',false) AS value`),false);
 assert.equal(await scalar(`SELECT ai_uses AS value FROM prompt_coach_daily_usage WHERE user_id='${user}'`),0);
 await assert.rejects(sql(`SELECT reserve_prompt_coach_ai_request('${request}','${user}')`),/duplicate key/);
});
test('successful requests cannot be refunded and daily limit is preserved',async()=> {
 for(let i=4;i<=6;i++) {
  const id=`00000000-0000-4000-8000-00000000000${i}`;
  await sql(`SELECT reserve_prompt_coach_ai_request('${id}','${user}'); SELECT settle_prompt_coach_ai_request('${id}','${user}',true);`);
  assert.equal(await scalar(`SELECT settle_prompt_coach_ai_request('${id}','${user}',false) AS value`),false);
 }
 await assert.rejects(sql(`SELECT reserve_prompt_coach_ai_request(gen_random_uuid(),'${user}')`),/daily limit/);
});
test('Quick Check strips keys and direct SELECT while server grades and retry is idempotent',async()=> {
 for(let i=0;i<6;i++) await sql(`INSERT INTO verification_cases(case_code,title,scenario,subskill,difficulty,case_type,correct_decision,explanation,learning_point,status) VALUES('case-${i}','Check AI claim ${i}','Verify this claim','claim_verification',1,'claim','supported','Grounded explanation','Check reliable sources','published')`);
 await sql('SET ROLE authenticated');
 const result=await scalar('SELECT create_adaptive_verification_session(4,1) AS value');
 assert.equal(result.cases.length,4);
 for(const item of result.cases) {
  for(const key of ['correct_decision','explanation','learning_point','evidence','actions','expected_confidence']) assert.ok(!(key in item),key);
  assert.equal(item.answer_hidden,true); assert.equal(item.decision_options.length,7);
 }
 assert.equal(await scalar('SELECT count(*)::int AS value FROM verification_cases'),0);
 const id=result.cases[0].case_id;
 const first=await scalar(`SELECT submit_verification_guess('${result.session_id}','${id}','supported') AS value`);
 assert.equal(first.decision_correct,true); assert.equal(first.correct_decision,'supported'); assert.equal(first.explanation,'Grounded explanation');
 const retry=await scalar(`SELECT submit_verification_guess('${result.session_id}','${id}','unverified') AS value`);
 assert.equal(retry.decision_correct,true);
 await sql(`SELECT set_config('test.uid','${other}',false)`);
 await assert.rejects(sql(`SELECT submit_verification_guess('${result.session_id}','${id}','supported')`),/active learner session/);
 await sql(`RESET ROLE; SELECT set_config('test.uid','${user}',false);`);
 assert.equal(await scalar(`SELECT count(*)::int AS value FROM verification_case_attempts WHERE case_id='${id}'`),1);
});
test('quiz grading rejects forged correctness, wrong identity, invalid index; counts valid answer once',async()=> {
 await sql(`INSERT INTO content_items(id,content_type,title,question,options,correct_index,explanation,adaptive_topic,status) VALUES('secure-quiz','quiz','Quiz','Choose the answer','["A","B","C","D"]',1,'B is correct','context','published'); SET ROLE authenticated;`);
 const call=(id,correct,index)=>`SELECT record_adaptive_answer('${id}','secure-quiz','context',${correct},'quiz',true,now(),${index}) AS value`;
 await assert.rejects(sql(call(other,true,1)),/Unauthorized/);
 await assert.rejects(sql(call(user,true,0)),/does not match/);
 await assert.rejects(sql(call(user,true,9)),/Invalid quiz/);
 assert.equal(await scalar(call(user,true,1)),true);
 assert.equal(await scalar(call(user,true,1)),false);
 await assert.rejects(sql(`SELECT record_adaptive_attempt('${user}','secure-quiz','context',true,'quiz',true,now())`),/permission denied/);
 assert.equal(await scalar(call(user,true,'null')),false);
 await sql('RESET ROLE');
});
test('diagnostic validates the complete key and derives all metrics without overwriting history',async()=> {
 const answers={diagnostic_prompt_clarity:1,diagnostic_context:1,diagnostic_specificity:0,diagnostic_responsible_use:2,diagnostic_verification:1};
 const call=(payload,score=100,total=5)=>`SELECT record_adaptive_diagnostic('${user}',${score},5,${total},'${JSON.stringify(payload)}',now()) AS value`;
 await sql('SET ROLE authenticated');
 await assert.rejects(sql(call({...answers,diagnostic_context:0})),/totals do not match/);
 await assert.rejects(sql(call({...answers,forged:1})),/five known/);
 const incomplete={...answers};delete incomplete.diagnostic_context;
 await assert.rejects(sql(call(incomplete)),/five known/);
 await assert.rejects(sql(call({...answers,diagnostic_context:9})),/Invalid diagnostic/);
 await assert.rejects(sql(call(answers,99)),/totals do not match/);
 assert.equal(await scalar(call(answers)),true);
 assert.equal(await scalar(call(answers)),false);
 await sql('RESET ROLE');
 assert.equal(await scalar(`SELECT score AS value FROM assessment_attempts WHERE user_id='${user}'`),100);
});
test('trusted diagnostic key matches the current Flutter item contract',()=>{
 const dart=read('lib/data/models/adaptive_learning.dart');
 const entries=[...dart.matchAll(/id: '(diagnostic_\w+)'[\s\S]*?correctIndex: (\d+)/g)].map(m=>[m[1],Number(m[2])]);
 const migration=read('supabase/migrations/20261019132000_assessment_answer_validation.sql');
 const key=JSON.parse(migration.match(/keys constant jsonb := '([^']+)'/)[1]);
 assert.equal(entries.length,5); assert.deepEqual(Object.fromEntries(entries),key);
});
 test.after(async()=>db.close());

}
