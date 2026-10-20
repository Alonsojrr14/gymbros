// Gera as artes de .work/jobs.json no ChatGPT, pelo Chrome aberto com ./chrome.sh (CDP na porta 9333).
// Uso: node gerar.mjs [abas] [arquivo.png...]   (pula o que já existe em .work/raw)
import { chromium } from 'playwright-core';
import fs from 'fs';
import path from 'path';
const WORK = process.env.ARTES_WORK || path.join(path.dirname(new URL(import.meta.url).pathname), '.work');
const jobs = JSON.parse(fs.readFileSync(`${WORK}/jobs.json`, 'utf8'));
fs.mkdirSync(`${WORK}/logs`, { recursive: true });
const TABS = +(process.argv[2] || 1), only = process.argv.slice(3);
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const b = await chromium.connectOverCDP('http://localhost:9333');
const ctx = b.contexts()[0];

async function gen(page, j) {
  await page.goto('https://chatgpt.com/', { waitUntil: 'domcontentloaded' });
  const box = page.locator('[contenteditable=true][aria-label="Pergunte ao ChatGPT"], #prompt-textarea').first();
  await box.waitFor({ timeout: 60000 });
  await page.locator('input[type=file][aria-label="Anexar fotos"]').setInputFiles(j.refs);
  await page.waitForTimeout(2000);
  await box.click();
  // o ChatGPT guarda rascunho entre conversas: limpa antes de colar e confere que ficou só este prompt
  await page.keyboard.press('Meta+A'); await page.keyboard.press('Backspace');
  await page.evaluate(t => document.execCommand('insertText', false, t), j.prompt);
  await page.waitForTimeout(500);
  const typed = await box.innerText();
  if (typed.split('Generate ONE image').length !== 2 || !typed.includes(j.prompt.slice(-200).trim().slice(0, 80)))
    return 'caixa com texto errado: ' + typed.slice(0, 150);
  const send = page.locator('[data-testid="send-button"], button[aria-label="Enviar prompt"], button[aria-label="Enviar mensagem"]').first();
  for (let i = 0; i < 120 && !(await send.count() && await send.isEnabled()); i++) await page.waitForTimeout(1000); // espera upload
  if (await send.count()) await send.click(); else await box.press('Enter');
  // espera terminar: some o botão de parar e existe imagem gerada
  const t0 = Date.now();
  await page.waitForTimeout(15000);
  while (Date.now() - t0 < 6 * 60000) {
    const busy = await page.locator('[data-testid="stop-button"], button[aria-label*="Parar"], button[aria-label*="Stop"]').count();
    const src = await page.evaluate(() => {
      const imgs = [...document.querySelectorAll('[data-message-author-role="assistant"] img, div[id^="image-"] img, img[alt*="erad"], img[alt*="enerated"]')]
        .filter(i => i.naturalWidth >= 512 && !/blur/.test(getComputedStyle(i).filter || ''));
      return imgs.length ? imgs[imgs.length - 1].src : null;
    });
    const limit = await page.evaluate(() => {
      const t = [...document.querySelectorAll('[data-message-author-role="assistant"]')].pop()?.innerText || '';
      return /limite (diário|de geração)|daily limit|usage limit|reached.*limit/i.test(t) ? t.slice(0, 200) : '';
    });
    if (limit) return 'limite: ' + limit.replace(/\n/g, ' ');
    const refused = await page.evaluate(() => {
      const t = [...document.querySelectorAll('[data-message-author-role="assistant"]')].pop()?.innerText || '';
      return /não consegui gerar|couldn.t generate|unable to generate|não foi possível gerar/i.test(t) ? t.slice(0, 200) : '';
    });
    if (refused) return 'sem imagem: ' + refused.replace(/\n/g, ' ');
    if (!busy && src) {
      // confere que esta conversa é a deste job (com várias abas o ChatGPT chegou a misturar conversas)
      const key = j.prompt.match(/It is an? ([^:]+):/)?.[1] || '';
      const mine = await page.evaluate(k => { const t = document.querySelector('main')?.innerText || ''; return t.includes(k) && t.split('Generate ONE image').length === 2; }, key);
      if (!mine) {
        const dbg = await page.evaluate(() => ({ url: location.href, users: [...document.querySelectorAll('[data-message-author-role="user"]')].map(m => m.textContent.length + ':' + m.textContent.slice(0, 120)), all: document.querySelector('main')?.innerText.slice(0, 600) }));
        return 'conversa errada (' + key + ') ' + JSON.stringify(dbg);
      }
      const b64 = await page.evaluate(async s => { const r = await fetch(s); const a = new Uint8Array(await r.arrayBuffer()); let x = ''; for (let i = 0; i < a.length; i += 32768) x += String.fromCharCode(...a.subarray(i, i + 32768)); return btoa(x); }, src);
      fs.writeFileSync(j.out + '.tmp', Buffer.from(b64, 'base64')); fs.renameSync(j.out + '.tmp', j.out);
      return 'ok';
    }
    if (!busy && Date.now() - t0 > 60000) {
      const txt = await page.locator('[data-message-author-role="assistant"]').last().innerText().catch(() => '');
      if (txt.trim()) return 'sem imagem: ' + txt.trim().slice(0, 300).replace(/\n/g, ' ');
    }
    await page.waitForTimeout(5000);
  }
  return 'timeout';
}

let queue = jobs.filter(j => !fs.existsSync(j.out) && (!only.length || only.includes(j.fname)));
queue.sort((a, b) => (a.stage > b.stage) - (a.stage < b.stage)); // champions primeiro
log('fila', queue.length);
let stop = false, streak = 0;
async function worker(k) {
  const page = await ctx.newPage();
  while (!stop) {
    const i = queue.findIndex(j => j.stage === 'champion' || fs.existsSync(j.refs[0]));
    if (i < 0) break;
    const j = queue.splice(i, 1)[0];
    let r;
    try { r = await gen(page, j); } catch (e) { r = 'erro: ' + String(e).slice(0, 200); }
    log(`[${k}]`, r === 'ok' ? 'ok' : 'FALHOU', j.fname, r === 'ok' ? '' : r);
    streak = r === 'ok' ? 0 : streak + 1;
    // várias falhas seguidas = cota acabou (a mensagem de limite nem sempre aparece): para e deixa o lote-viradas.sh esperar
    if (streak >= 8) { log('8 falhas seguidas, parando'); stop = true; }
    if (r !== 'ok') {
      await page.screenshot({ path: `${WORK}/logs/${j.fname}.png` }).catch(() => {});
      if (/limit|limite|try again|tente novamente|plano|upgrade/i.test(r)) { log('LIMITE atingido, parando'); stop = true; }
    }
  }
  await page.close().catch(() => {});
}
await Promise.all([...Array(TABS)].map((_, k) => worker(k)));
log('FIM', jobs.filter(j => fs.existsSync(j.out)).length, '/', jobs.length);
process.exit(0);
