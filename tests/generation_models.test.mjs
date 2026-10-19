import test from 'node:test';
import assert from 'node:assert/strict';
import {isTextGenerationModel,orderTextModels,disableUnavailableModel} from '../supabase/functions/content-automation/models.mjs';
test('speech/safety models including the screenshot Orpheus model are excluded',()=>{
 for(const id of ['canopylabs/orpheus-v1-english','playai-tts','whisper-large-v3','llama-guard','audio-model','vision-model']) assert.equal(isTextGenerationModel(id),false,id);
 assert.deepEqual(orderTextModels(['openai/gpt-oss-20b','canopylabs/orpheus-v1-english','llama-3.1-8b-instant'],'canopylabs/orpheus-v1-english'),['llama-3.1-8b-instant','openai/gpt-oss-20b']);
});
test('rate-limited models are removed for the rest of the run without retrying per article',()=>{
 const models=['llama-3.1-8b-instant','openai/gpt-oss-20b'];
 disableUnavailableModel(models,models[0],429);assert.deepEqual(models,['openai/gpt-oss-20b']);
 disableUnavailableModel(models,models[0],400);assert.deepEqual(models,[]);
});
