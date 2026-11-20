// Read-only store price preview. Never logs or saves service-account credentials/tokens.
import { readFile, writeFile } from 'node:fs/promises';
import { createSign } from 'node:crypto';
const credentials = JSON.parse(await readFile(process.argv[2], 'utf8'));
if (credentials.project_id !== 'crispy-crust-514821' || credentials.token_uri !== 'https://oauth2.googleapis.com/token') throw Error('Unexpected credential target');
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const data = `${encode({alg:'RS256',typ:'JWT'})}.${encode({iss:credentials.client_email,scope:'https://www.googleapis.com/auth/androidpublisher',aud:credentials.token_uri,iat:now,exp:now+600})}`;
const signature = createSign('RSA-SHA256').update(data).sign(credentials.private_key).toString('base64url');
const tokenResponse = await fetch(credentials.token_uri,{method:'POST',body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${data}.${signature}`})});
const token = await tokenResponse.json();
if (!tokenResponse.ok || !token.access_token) throw Error(`Google authentication failed (${tokenResponse.status})`);
const output = {};
for (const [plan, gross] of [['monthly',2.99],['annual',29.99]]) {
  // The conversion API requires a tax-exclusive source. UK standard VAT is 20%.
  const net = gross / 1.2;
  const units = Math.floor(net), nanos = Math.round((net-units)*1e9);
  const response = await fetch('https://androidpublisher.googleapis.com/androidpublisher/v3/applications/app.crispycrust.mobile/pricing:convertRegionPrices',{
    method:'POST',headers:{authorization:`Bearer ${token.access_token}`,'content-type':'application/json'},
    body:JSON.stringify({price:{currencyCode:'GBP',units:String(units),nanos}}),
  });
  const result = await response.json();
  if (!response.ok) throw Error(`Price preview failed (${response.status}): ${result.error?.message ?? 'Unknown'}`);
  output[plan] = result;
}
await writeFile(process.argv[3],JSON.stringify(output,null,2));
console.log(JSON.stringify(Object.fromEntries(Object.entries(output).map(([plan,result])=>[plan,{regions:Object.keys(result.convertedRegionPrices).length,GB:result.convertedRegionPrices.GB}]))));
