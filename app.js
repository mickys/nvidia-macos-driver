// Game test review page: loads data.json (built by build.py after each game), lists games, shows screenshots + stats.
'use strict';
let DATA = null, SEL = null;
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const cls = st => ['works','runs','fails','crash','testing','pending'].includes(st) ? 's-' + st : 's-other';

async function load() {
  try {
    const r = await fetch('data.json?t=' + Date.now(), {cache: 'no-store'});
    DATA = await r.json();
  } catch (e) { $('#summary').textContent = 'could not load data.json: ' + e; return; }
  const sel = $('#st'), have = new Set([...sel.options].map(o => o.value));
  Object.keys(DATA.counts).forEach(k => { if (!have.has(k)) sel.add(new Option(k, k)); });
  const c = DATA.counts, n = DATA.games.length, done = n - (c.pending || 0) - (c.testing || 0);
  $('#summary').innerHTML = `Updated <b>${esc(DATA.updated)}</b> · tested <b>${done}</b> / ${n} · ` +
    Object.entries(c).map(([k, v]) => `<span class="${cls(k)}">${esc(k)} <b>${v}</b></span>`).join(' · ');
  keepInPlace(SEL, render);
}

function render() {
  const q = $('#q').value.toLowerCase(), st = $('#st').value;
  const rows = DATA.games.filter(g => (!q || g.name.toLowerCase().includes(q)) && (!st || g.status === st));
  $('#list tbody').innerHTML = rows.map(g => `
    <tr class="row ${g.appid === SEL ? 'sel' : ''}" data-id="${g.appid}">
      <td class="num">${g.rank}</td><td>${esc(g.name)}</td>
      <td><span class="badge ${cls(g.status)}">${esc(g.status)}</span></td>
      <td class="num">${esc(g.menu_fps || '')}</td><td class="num">${esc(g.game_fps || '')}</td>
      <td class="num">${esc(g.cpu_peak || '')}</td><td class="num">${esc(g.rss_peak_mb || '')}</td><td class="num">${esc(g.vram_peak_mb || '')}</td>
      <td class="num">${g.shots.length || ''}</td><td class="fix">${fixHTML(g)}</td><td class="notes">${esc(g.notes || '')}</td>
    </tr>${g.appid === SEL ? `<tr class="detail-row"><td colspan="11"><div id="detail">${detailHTML(g)}</div></td></tr>` : ''}`).join('');
  document.querySelectorAll('tr.row').forEach(tr => tr.onclick = e => { if (!e.target.closest('a')) toggle(tr.dataset.id); });
  document.querySelectorAll('#detail .shot img').forEach((img, i) => img.onclick = () => showShot(i));
  const perms = DATA.permissions || [];
  $('#perms').innerHTML = perms.length ? `<h3>macOS permission prompts answered during the tests</h3><table><tr><th>Time</th><th>App</th><th>Permission</th><th>Answer</th></tr>` +
    perms.map(p => `<tr><td>${esc(p.time)}</td><td>${esc(p.app)}</td><td>${esc(p.permission)}</td><td>${esc(p.answer)}</td></tr>`).join('') + '</table>' : '';
}

// the fork branches a game needs on top of NullMoth's release (links to each branch's diff), or a non-driver note
const branchLink = b => `<a href="${esc(DATA.fix_repo)}/compare/${esc(DATA.fix_base)}...${esc(b)}" target="_blank" rel="noopener" title="changes against ${esc(DATA.fix_base_name)}">${esc(b)}</a>`;
function fixHTML(g) {
  const br = g.fix_branches || [];
  return br.length ? br.map(branchLink).join('<br>') : (g.fix_note ? `<span class="fixnote">${esc(g.fix_note)}</span>` : '');
}

// one game's details, opened under its row
function detailHTML(g) {
  return `<h2>#${g.rank} ${esc(g.name)} <span class="badge ${cls(g.status)}">${esc(g.status)}</span></h2>
    <div class="kv">Steam appid <b>${g.appid}</b> · menu fps <b>${esc(g.menu_fps || '–')}</b> · in-game fps <b>${esc(g.game_fps || '–')}</b> ·
      CPU peak <b>${esc(g.cpu_peak || '–')}%</b> · RAM peak <b>${esc(g.rss_peak_mb || '–')} MB</b> · VRAM peak <b>${esc(g.vram_peak_mb || '–')} MB</b> ·
      driver issues <b>${esc(g.driver_issues || '–')}</b></div>
    ${(g.fix_branches || []).length ? `<div class="kv">Needs fork branches (on ${esc(DATA.fix_base_name)}): ${g.fix_branches.map(branchLink).join(' · ')} · ${esc(g.fix_note)}</div>` : ''}
    ${g.notes ? `<div>${esc(g.notes)}</div>` : ''}
    <div class="shots">${g.shots.map(s => `<div class="shot">
      <img loading="lazy" src="${esc(s.thumb)}" data-full="${esc(s.file)}" data-cap="${esc(g.name)} · ${esc(s.idx)} ${esc(s.label)} · ${esc(s.note)}">
      <div class="meta"><b>${esc(s.idx)} ${esc(s.label)}</b> ${esc(s.time)} · ${esc(s.note)}<br>
        fps <b>${esc(s.display_fps)}</b> · CPU <b>${esc(s.cpu)}%</b> · RAM <b>${esc(s.rss_mb)} MB</b> · GPU <b>${esc(s.gpu_util)}%</b> · VRAM <b>${esc(s.vram_mb)} MB</b>${s.alive === '0' ? ' · <span class="s-fails">not running</span>' : ''}</div>
    </div>`).join('')}</div>
    ${g.info ? `<h3>Build info</h3><pre>${esc(g.info)}</pre>` : ''}
    ${g.check ? `<h3>Driver log check</h3><pre>${esc(g.check)}</pre>` : ''}`;
}

// re-render with the row of game `id` at the same place on screen (opening or closing a game above it changes the height)
function keepInPlace(id, fn) {
  const row = () => id && document.querySelector(`tr.row[data-id="${id}"]`);
  const r0 = row(), y0 = r0 ? r0.getBoundingClientRect().top : null;
  fn();
  const r1 = row();
  if (y0 !== null && r1) window.scrollBy(0, r1.getBoundingClientRect().top - y0);
}

// click on a game: open its details in place (closing the open one), or close them
function toggle(id) {
  SEL = SEL === id ? null : id;
  keepInPlace(id, render);
}

// full-size screenshot i of the open game; left / right keys step through them
let SHOT = 0;
function showShot(i) {
  const imgs = [...document.querySelectorAll('#detail .shot img')]; if (!imgs.length) return;
  SHOT = (i + imgs.length) % imgs.length; const img = imgs[SHOT], lb = $('#lightbox');
  lb.querySelector('img').src = img.dataset.full;
  lb.querySelector('.cap').textContent = `${img.dataset.cap}  (${SHOT + 1} / ${imgs.length}, ← → for previous / next)`;
  lb.hidden = false;
  [-1, 1].forEach(d => { new Image().src = imgs[(SHOT + d + imgs.length) % imgs.length].dataset.full; });   // preload the neighbours
}

$('#lightbox').onclick = () => { $('#lightbox').hidden = true; };
document.addEventListener('keydown', e => {
  if (!$('#lightbox').hidden && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) { e.preventDefault(); showShot(SHOT + (e.key === 'ArrowLeft' ? -1 : 1)); return; }
  if (e.key !== 'Escape') return;
  if (!$('#lightbox').hidden) $('#lightbox').hidden = true; else if (SEL) toggle(SEL);
});
$('#q').oninput = render; $('#st').onchange = render;
setInterval(() => { if ($('#auto').checked && $('#lightbox').hidden) load(); }, 60000);
load();
// the column headings stick right under the header, whatever its height (it wraps on narrow windows)
const hdr = () => document.documentElement.style.setProperty('--hdr', $('header').offsetHeight + 'px');
window.addEventListener('resize', hdr); hdr();
