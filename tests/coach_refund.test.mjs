import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
let handler;
globalThis.Deno={serve:fn=>handler=fn,env:{get:name=>({SUPABASE_URL:'https://fixture.invalid',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'service-only',GROQ_API_KEY:'fixture',GROQ_MODEL:'fixture-model'})[name]}};
await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(readFileSync(new URL('../supabase/functions/promptwise-integrations/index.ts',import.meta.url),'utf8'))).toString('base64')}`);
const guidance={summary:'Review your task.',focus_areas:['Context'],guiding_questions:['Who is the audience?','What background matters?'],reasoning_notes:['Audience guides wording.','Context limits assumptions.'],next_challenge:'Identify the reader.'};
async function run({providerFails=false,missing=false,denied=false,settleFails=false,cancelled=false}={}) {
 const calls=[];
 const cancellation = new AbortController();
 globalThis.fetch=async(url,options={})=> {
  url=String(url);
  if(url.includes('/auth/')) return Response.json({id:'authenticated-user'});
  if(url.includes('/chat/completions')) {
   if(cancelled) { cancellation.abort(); assert.equal(options.signal.aborted,true); throw new DOMException('Cancelled','AbortError'); }
   return providerFails ? new Response('Provider failed',{status:503}) : Response.json({choices:[{message:{content:JSON.stringify(guidance)}}]});
  }
  const name=url.split('/').at(-1); const body=JSON.parse(options.body ?? '{}');
  calls.push({name,body,authorization:options.headers.Authorization});
  if(name==='reserve_prompt_coach_ai_request') {
   if(missing) return Response.json({code:'PGRST202',message:'Could not find the function'},{status:404});
   if(denied) return new Response('permission denied',{status:403});
  }
  if(name==='settle_prompt_coach_ai_request') return settleFails ? new Response('Unavailable',{status:503}) : Response.json(true);
  return Response.json({used:1,limit:3,remaining:2});
 };
 const response=await handler(new Request('https://fixture.invalid?method=coach',{method:'POST',signal:cancellation.signal,headers:{Authorization:'Bearer learner'},body:JSON.stringify({prompt:'Explain photosynthesis to a Grade 8 student.'})}));
 return {calls,status:response.status,data:await response.json()};
}
test('Edge reserves with authenticated identity, never caller identity; settles successful request',async()=> {
 const {calls,status}=await run(); assert.equal(status,200);
 const reserve=calls.find(c=>c.name==='reserve_prompt_coach_ai_request');
 assert.equal(reserve.body.p_user_id,'authenticated-user'); assert.equal(reserve.authorization,'Bearer service-only');
 assert.equal(calls.find(c=>c.name==='settle_prompt_coach_ai_request').body.p_success,true);
});
test('failed provider refunds the same backend request exactly once',async()=> {
 const {calls,status}=await run({providerFails:true});assert.equal(status,502);
 const reserve=calls[0],settle=calls.at(-1);assert.equal(settle.body.p_request_id,reserve.body.p_request_id);
 assert.equal(settle.body.p_success,false);assert.equal(calls.filter(c=>c.name==='settle_prompt_coach_ai_request').length,1);
});
test('rollout fallback works only while the new RPC is absent',async()=> {
 const {calls,status}=await run({missing:true,providerFails:true});assert.equal(status,502);
 assert.ok(calls.some(c=>c.name==='reserve_prompt_coach_ai_use'));
 assert.ok(calls.some(c=>c.name==='refund_prompt_coach_ai_use'));
 const denied=await run({denied:true});assert.equal(denied.status,500);
 assert.ok(!denied.calls.some(c=>c.name==='reserve_prompt_coach_ai_use'));
});
test('failed settlement never falsely promises that quota was refunded',async()=> {
 const {data}=await run({providerFails:true,settleFails:true});
 assert.match(data.message,/reconciliation is pending/); assert.doesNotMatch(data.message,/was not consumed/);
});
test('an observed request cancellation follows the same backend-authorized refund path',async()=> {
 const {calls,status}=await run({cancelled:true});assert.equal(status,502);
 assert.equal(calls.at(-1).body.p_success,false);
});
