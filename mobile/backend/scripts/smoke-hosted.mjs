import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const config=JSON.parse(await readFile(new URL('../../config/development.json',import.meta.url),'utf8'));
const origin=new URL(config.SUPABASE_URL);
assert.equal(origin.protocol,'https:');
const endpoint=new URL('/functions/v1/app-api/v1/kitchens',origin);
async function request(url,headers={}) {
 const response=await fetch(url,{headers,redirect:'error',signal:AbortSignal.timeout(20000)});
 return {status:response.status,body:await response.text()};
}
const missing=await request(endpoint);
assert.equal(missing.status,401,'Anonymous app API must be denied');
assert.match(missing.body,/AUTH_REQUIRED/);
const invalid=await request(endpoint,{Authorization:'Bearer invalid-development-test-token'});
assert.equal(invalid.status,401,'Invalid access token must be denied');
const wrongOrigin=await request(endpoint,{Origin:'https://untrusted.invalid'});
assert.equal(wrongOrigin.status,403,'Unapproved browser origin must be denied');
for(const table of ['cc_kitchens','cc_profiles','crumb_clock_waitlist']) {
 const result=await request(new URL(`/rest/v1/${table}?select=*&limit=1`,origin),{apikey:config.SUPABASE_PUBLISHABLE_KEY});
 assert.ok([401,403].includes(result.status),`Anonymous Data API access to ${table} must be denied (got ${result.status})`);
}
console.log('Hosted app API and Data API reject missing/invalid auth and unapproved origins; legacy waitlist remains private.');
