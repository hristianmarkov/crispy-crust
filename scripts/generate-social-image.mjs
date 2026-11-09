import sharp from "sharp";
const photo = await sharp("public/images/sourdough.webp")
  .resize(385, 500, { fit: "cover" })
  .composite([
    {
      input: Buffer.from(
        '<svg width="385" height="500"><path fill="white" d="M192.5 0A192.5 192.5 0 0 1 385 192.5V490Q385 500 375 500H10Q0 500 0 490V192.5A192.5 192.5 0 0 1 192.5 0Z"/></svg>',
      ),
      blend: "dest-in",
    },
  ])
  .png()
  .toBuffer();
const text = Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630"><g fill="#30352a"><text x="65" y="110" font-family="DejaVu Serif" font-size="28">crumb &amp; clock</text><text x="60" y="290" font-family="DejaVu Serif" font-size="79" letter-spacing="-4">Good bread.</text><text x="60" y="385" font-family="DejaVu Serif" font-size="79" fill="#62714c" letter-spacing="-4">On your time.</text><text x="65" y="550" font-family="DejaVu Sans" font-size="19" fill="#6c755f">Your sourdough sidekick. Coming soon.</text></g></svg>`,
);
await sharp({
  create: { width: 1200, height: 630, channels: 3, background: "#f8f7f0" },
})
  .composite([{ input: photo, left: 750, top: 65 }, { input: text }])
  .jpeg({ quality: 90 })
  .toFile("public/images/social-card.jpg");
