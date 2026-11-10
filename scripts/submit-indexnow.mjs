import { readFile } from 'node:fs/promises';

const origin = 'https://www.crispycrust.app';
const key = (await readFile(new URL('./indexnow-key.txt', import.meta.url), 'utf8')).trim();
if (!/^[a-f0-9]{32}$/.test(key)) throw new Error('Invalid IndexNow key');
const expectedCommit = process.env.EXPECTED_COMMIT;
if (expectedCommit) {
  if (!/^[a-f0-9]{40}$/.test(expectedCommit)) throw new Error('Invalid publication commit');
  let published = false;
  for (let attempt = 0; attempt < 45; attempt++) {
    try {
      const response = await fetch(`${origin}/.well-known/site-release.json?release=${expectedCommit}`, {
        cache: 'no-store', signal: AbortSignal.timeout(20_000),
      });
      if (response.ok && (await response.json()).commit === expectedCommit) {
        published = true;
        break;
      }
    } catch { /* The previous deployment can still be serving during publication. */ }
    console.log(`Waiting for production publication (${attempt + 1}/45).`);
    await new Promise((resolve) => setTimeout(resolve, 10_000));
  }
  if (!published) throw new Error('The expected production release is not live; no URLs were submitted');
}
const proof = await fetch(`${origin}/${key}.txt`);
if (!proof.ok || (await proof.text()).trim() !== key) throw new Error('The IndexNow ownership key is not live on the canonical host yet');
const sitemap = await fetch(`${origin}/sitemap.xml`);
if (!sitemap.ok) throw new Error(`Sitemap returned ${sitemap.status}`);
const urlList = [...(await sitemap.text()).matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1].replaceAll('&amp;', '&'));
if (!urlList.length || urlList.some((url) => new URL(url).origin !== origin)) throw new Error('Expected canonical URLs in the sitemap');
const response = await fetch('https://api.indexnow.org/indexnow', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ host: 'www.crispycrust.app', key, keyLocation: `${origin}/${key}.txt`, urlList }),
});
console.log(`IndexNow: HTTP ${response.status}; ${urlList.length} canonical URLs submitted.`);
if (![200, 202].includes(response.status)) throw new Error(`IndexNow did not accept the submission: ${await response.text()}`);
