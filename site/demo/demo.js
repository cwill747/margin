/* App-only demo. Keep palettes and interactions aligned with the native app.
   No workspace credentials, network requests, or external runtime dependencies. */
'use strict';
const $ = id => document.getElementById(id);
const KEY = 'margin-web-demo-v2';
const collections = {'getting-started': 'Welcome', ideas: 'Ideas & research'};
const samples = [
  {id:'welcome', collection:'getting-started', title:'What is Outline', text:'Outline is a place to build your team knowledge base, you could think of it like your team’s shared library – a place for important documentation, notes, and ideas to live and be discovered. Some things you might want to keep in Outline include:\n\n- Documentation\n- Support knowledge base\n- Product plans and RFCs\n- Sales playbooks\n- Onboarding checklists\n- Company policies\n- Meeting notes\n\n## Structure\n\nOutline allows you to organize documents in "collections", for example these could represent topics like Sales, Product, or HR. You can assign users or groups access to collections.'},
  {id:'getting-started', collection:'getting-started', title:'Getting Started', text:'A little structure goes a long way. Start with a collection, add your first document, and give your team a place to find what matters.\n\n## Make yourself at home\n\n- Browse the pages in the sidebar.\n- Choose a page to start reading.\n- Keep a reference beside your document.\n\n## Room for a second thought\n\nUse **Keep beside** in the right-hand toolbar, then open another page. Your reference stays close as you explore.\n\n> Fold the Duo to switch between your document and reference without losing your place.'},
  {id:'editor', collection:'getting-started', title:'Our Editor', text:'Great documentation starts with a clear thought. Margin gives you a quiet place to write it down.\n\n## Write in Markdown\n\nUse **bold** for emphasis, *italics* for a softer note, and headings to give your page structure.\n\n- Start a new document with the compose button.\n- Edit this page with the pencil button.\n- Save when you are ready.\n\n## Keep your place\n\nUnfinished drafts stay in this browser. Leave the editor and come back when the next sentence arrives.'},
  {id:'integrations', collection:'getting-started', title:'Integrations & API', text:'Your knowledge belongs where you need it. Margin connects to your Outline workspace so your documents are comfortably within reach.\n\n## Connect your workspace\n\nIn the native app, enter your workspace address and choose **Sign in to Outline**.\n\n## This sample workspace\n\nThis interactive demo runs entirely in your browser. Read, edit, and save sample documents without connecting an account.'},
  {id:'field-notes', collection:'ideas', title:'Field notes', text:'Good ideas rarely arrive at a desk.\n\n## A small ritual\n\n- Keep a question close.\n- Collect the surprising details.\n- Leave room for a second thought.\n\n## Connect the dots\n\nKeep this page beside another document to compare your notes.'}
];
const paths = {
  profile:'<circle cx="12" cy="12" r="10"/><circle cx="12" cy="9" r="3" fill="currentColor" stroke="none"/><path d="M5 19c1-6 13-6 14 0A10 10 0 0 1 5 19" fill="currentColor" stroke="none"/>',
  sidebar:'<rect x="2" y="4" width="20" height="16" rx="2"/><path d="M9 4v16M5 8h1M5 11h1M5 14h1"/>',
  page:'<path d="M14 2H5a1 1 0 0 0-1 1v18a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V8zM14 2v7h6M8 14h8M8 18h8"/>',
  edit:'<path d="M15 4H6a3 3 0 0 0-3 3v11a3 3 0 0 0 3 3h11a3 3 0 0 0 3-3V9M10 14l2-5L20 1l3 3-8 8z"/>',
  search:'<circle cx="10" cy="10" r="7"/><path d="m15 15 7 7"/>',
  split:'<rect x="2" y="4" width="20" height="16" rx="1.5"/><path d="M12 4v16"/>',
  save:'<circle cx="12" cy="12" r="9"/><path d="M12 6v12m-5-5 5 5 5-5"/>',
  check:'<circle cx="12" cy="12" r="9"/><path d="m7 12 4 5 6-10"/>',
  share:'<path d="M8 8H6a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V10a2 2 0 0 0-2-2h-2M12 15V1M7 6l5-5 5 5"/>',
  back:'<path d="m15 4-8 8 8 8"/>',
  chevron:'<path d="m6 9 6 6 6-6"/>'
};
function icon(name) { return `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name]}</svg>`; }
const fresh = () => ({documents: structuredClone(samples), selected: 'welcome', reference: null, saved: [], theme: 'paper', fontSize: 18, folded: window.matchMedia('(max-width: 600px)').matches, draft: null});
let state = fresh();
let storageAvailable = true;
try {
  const value = JSON.parse(localStorage.getItem(KEY));
  if (value && Array.isArray(value.documents) && value.documents.length && value.documents.every(d => d && ['id','title','text','collection'].every(k => typeof d[k] === 'string') && collections[d.collection])) {
    state = {...fresh(), ...value};
    if (!state.documents.some(d => d.id === state.selected)) state.selected = state.documents[0].id;
    if (!state.documents.some(d => d.id === state.reference)) state.reference = null;
    state.saved = Array.isArray(state.saved) ? state.saved.filter(id => state.documents.some(d => d.id === id)) : [];
    if (!['paper','sepia','night','system'].includes(state.theme)) state.theme = 'paper';
    state.fontSize = Math.min(30, Math.max(14, Number(state.fontSize) || 18));
    if (state.draft && (!['title','text','collection'].every(k => typeof state.draft[k] === 'string') || !collections[state.draft.collection] || (state.draft.id !== null && typeof state.draft.id !== 'string'))) state.draft = null;
  }
} catch { storageAvailable = false; }
let libraryOpen = true, savedOnly = false, referenceActive = false, editing = false;
const scrollPositions = new Map();
function announce(message) { $('announcement').textContent = message; }
function persist() {
  try { localStorage.setItem(KEY, JSON.stringify(state)); }
  catch { storageAvailable = false; announce('Browser storage is unavailable. Changes last until this page closes.'); }
}
function escapeHTML(text) { return text.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function renderHTML(target, html) {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  target.replaceChildren(...parsed.body.childNodes);
}
// Escape first: editable sample content can never become executable HTML.
function inline(text) {
  return escapeHTML(text).replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>').replace(/\*([^*]+)\*/g, '<em>$1</em>').replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
}
function markdown(text) {
  return text.split(/\n\s*\n/).map(block => {
    if (/^#{1,3} /.test(block)) return block.split('\n').map(line => {
      const heading = line.match(/^(#{1,3}) (.*)$/);
      return heading ? `<h${heading[1].length}>${inline(heading[2])}</h${heading[1].length}>` : `<p>${inline(line)}</p>`;
    }).join('');
    if (block.split('\n').every(line => /^- /.test(line))) return `<ul>${block.split('\n').map(line => `<li>${inline(line.slice(2))}</li>`).join('')}</ul>`;
    if (/^> /.test(block)) return `<blockquote>${inline(block.replace(/^> /gm, '')).replace(/\n/g, '<br>')}</blockquote>`;
    return `<p>${inline(block).replace(/\n/g, '<br>')}</p>`;
  }).join('');
}
const doc = id => state.documents.find(d => d.id === id);
function captureScroll() {
  document.querySelectorAll('.page').forEach(el => { if (el.clientHeight) scrollPositions.set(el.dataset.scrollKey, el.scrollTop); });
}
function renderList() {
  const query = $('search').value.trim().toLowerCase();
  const visible = state.documents.filter(d => (!savedOnly || state.saved.includes(d.id)) && `${d.title} ${d.text}`.toLowerCase().includes(query));
  let listHTML = Object.entries(collections).map(([id, title]) => {
    const documents = visible.filter(d => d.collection === id);
    if (!documents.length) return '';
    const buttons = documents.map(d => {
      const current = d.id === state.selected ? 'aria-current="page"' : '';
      const savedLabel = state.saved.includes(d.id) ? '<small>Saved for reading</small>' : '';
      return `<button class="document-button" data-open="${escapeHTML(d.id)}" ${current}>${icon('page')}<span>${escapeHTML(d.title)}${savedLabel}</span></button>`;
    }).join('');
    return `<h2 class="collection">${title}${icon('chevron')}</h2>${buttons}`;
  }).join('');
  if (!listHTML) {
    const message = savedOnly ? 'No saved pages yet. Choose “Save offline” on a document.' : 'No matching pages. Try another search.';
    listHTML = `<p class="empty">${message}</p>`;
  }
  renderHTML($('document-list'), listHTML);
  $('all').setAttribute('aria-pressed', String(!savedOnly));
  $('saved').setAttribute('aria-pressed', String(savedOnly));
}
function renderReader(id, target) {
  const d = doc(id);
  if (!d) { target.replaceChildren(); return; }
  const saveLabel = state.saved.includes(id) ? 'Saved ✓' : 'Save offline';
  const toolbar = '<button data-action="pin" title="Keep this page as a reference while opening another">Keep beside</button><span class="spacer"></span>';
  const readerActions = `<button data-action="save">${saveLabel}</button><button data-action="edit">Edit</button>`;
  renderDocument(id, target, 'primary', toolbar, readerActions);
}
function renderReference(id, target) {
  const toolbar = '<span class="reference-label">Reference</span><span class="spacer"></span><button data-action="close-reference" aria-label="Close reference">Close</button>';
  renderDocument(id, target, 'reference', toolbar, '');
}
function renderDocument(id, target, scrollKey, toolbar, readerActions) {
  const d = doc(id);
  if (!d) { target.replaceChildren(); return; }
  renderHTML(target, `<div class="reader-toolbar">${toolbar}${readerActions}</div><article class="page" data-scroll-key="${scrollKey}:${escapeHTML(id)}"><div class="eyebrow">${collections[d.collection]}</div><h1>${escapeHTML(d.title)}</h1><div class="markdown">${markdown(d.text)}</div></article>`);
  const page = target.querySelector('.page');
  page.scrollTop = scrollPositions.get(page.dataset.scrollKey) || 0;
}
function render() {
  captureScroll();
  renderList();
  if (editing) renderEditor(); else renderReader(state.selected, $('primary'));
  renderReference(state.reference, $('reference'));
  renderHTML($('save-page'), icon(state.saved.includes(state.selected) ? 'check' : 'save'));
  $('save-page').setAttribute('aria-label', state.saved.includes(state.selected) ? 'Remove saved copy' : 'Save offline');
  $('save-page').title = $('save-page').getAttribute('aria-label');
  $('screen').classList.toggle('editing', editing);
  appearance();
  layout();
  requestAnimationFrame(() => document.querySelectorAll('.page').forEach(el => { if(el.clientHeight) el.scrollTop = scrollPositions.get(el.dataset.scrollKey) || 0; }));
}
function appearance() {
  $('screen').dataset.theme = state.theme;
  $('screen').style.setProperty('--reading-size', `${state.fontSize}px`);
  $('theme').value = state.theme;
  $('font-size').value = state.fontSize;
  $('font-value').textContent = `${state.fontSize} pt`;
}
function layout() {
  $('device').classList.toggle('folded', Boolean(state.folded));
  $('device').setAttribute('aria-label', state.folded ? 'Folded phone' : 'Unfolded phone');
  $('fold').textContent = state.folded ? 'Unfold phone' : 'Fold phone';
  $('fold').setAttribute('aria-pressed', String(Boolean(state.folded)));
  const logicalWidth = state.folded ? 466 : 951;
  const logicalHeight = state.folded ? 678 : 669;
  const bezel = state.folded ? 24 : 40;
  const scale = Math.min(1, document.querySelector('.stage').clientWidth / (logicalWidth + bezel));
  $('device').style.width = `${logicalWidth + bezel}px`;
  $('device').style.setProperty('--device-width', `${logicalWidth + bezel}px`);
  $('device').style.transform = `scale(${scale})`;
  $('screen').style.width = `${logicalWidth}px`;
  $('screen').style.height = `${logicalHeight}px`;
  document.querySelector('.stage').style.height = `${(logicalHeight + bezel) * scale}px`;
  const compact = Boolean(state.folded);
  $('readers').inert = compact && libraryOpen;
  $('workspace').classList.toggle('compact', compact);
  $('workspace').classList.toggle('library-closed', !libraryOpen);
  $('library-toggle').setAttribute('aria-expanded', String(libraryOpen));
  $('library-toggle').setAttribute('aria-label', libraryOpen ? 'Hide library' : 'Show library');
  $('library-toggle').title = libraryOpen ? 'Hide library' : 'Show library';
  // Match DuoReader's 760-point threshold for side-by-side readers.
  const paired = !state.folded && !libraryOpen && !editing;
  const hasReference = Boolean(state.reference) && !editing;
  $('pane-switch').hidden = !hasReference || paired;
  $('primary').hidden = hasReference && !paired && referenceActive;
  $('reference').hidden = !hasReference || (!paired && !referenceActive);
  $('document-tab').setAttribute('aria-pressed', String(!referenceActive));
  $('reference-tab').setAttribute('aria-pressed', String(referenceActive));
  $('hint').textContent = state.folded ? 'Same workspace, a smaller screen. Your pages and reading positions stay with you.' : 'A little more room. Keep a page beside another to compare them.';
}
function openDocument(id) {
  captureScroll();
  state.selected = id; referenceActive = false; editing = false;
  if (state.folded || state.reference) libraryOpen = false;
  persist(); render();
}
function startEditor(isNew) {
  captureScroll();
  const d = doc(state.selected);
  if (!state.draft) state.draft = isNew ? {id: null, title:'', text:'', collection:'ideas'} : {...d};
  else announce('Resumed your unfinished draft. Save or discard it before starting another.');
  editing = true; referenceActive = false; libraryOpen = false;
  persist(); render();
  $('edit-title').focus();
}
function renderEditor() {
  const draft = state.draft;
  renderHTML($('primary'), `<div class="reader-toolbar"><button data-action="cancel-edit">Back</button><span class="spacer"></span><button data-action="discard-edit">Discard</button><button class="solid" data-action="publish" ${draft.title.trim() ? '' : 'disabled'}>Save</button></div><div class="editor"><input id="edit-title" aria-label="Document title" placeholder="Untitled document" value="${escapeHTML(draft.title)}"><div class="formatting" aria-label="Markdown formatting"><button data-format="bold" aria-label="Bold"><strong>B</strong></button><button data-format="italic" aria-label="Italic"><em>I</em></button><button data-format="heading">Heading</button><button data-format="list">List</button><button data-format="quote">Quote</button></div><textarea id="edit-text" aria-label="Document Markdown" placeholder="Leave room for a thought…">${escapeHTML(draft.text)}</textarea><p class="editor-note">Markdown · Draft saved in this browser</p></div>`);
  const update = () => {
    state.draft.title = $('edit-title').value; state.draft.text = $('edit-text').value;
    $('primary').querySelector('[data-action=publish]').disabled = !state.draft.title.trim(); persist();
  };
  $('edit-title').addEventListener('input', update); $('edit-text').addEventListener('input', update);
}
$('document-list').addEventListener('click', event => {
  const button = event.target.closest('[data-open]'); if (button) openDocument(button.dataset.open);
});
$('readers').addEventListener('click', event => {
  const button = event.target.closest('button'); if (!button) return;
  const action = button.dataset.action;
  if (action === 'pin') {
    state.reference = state.selected; referenceActive = false; libraryOpen = true;
    announce('Reference kept. Open another page from the library to read them together.');
  } else if (action === 'close-reference') { state.reference = null; referenceActive = false; }
  else if (action === 'save') {
    const saved = state.saved.includes(state.selected);
    state.saved = saved ? state.saved.filter(id => id !== state.selected) : [...state.saved, state.selected];
    announce(saved ? 'Removed from saved reading.' : 'Page added to saved reading in this browser.');
  } else if (action === 'edit') { startEditor(false); return; }
  else if (action === 'cancel-edit') { editing = false; announce('Draft kept. Choose Edit or New document to resume.'); }
  else if (action === 'discard-edit') { state.draft = null; editing = false; announce('Draft discarded.'); }
  else if (action === 'publish') {
    if (!state.draft.title.trim()) return;
    const updated = {...state.draft, title:state.draft.title.trim(), id:state.draft.id || crypto.randomUUID()};
    const index = state.documents.findIndex(d => d.id === updated.id);
    if (index >= 0) state.documents[index] = updated; else state.documents.push(updated);
    state.selected = updated.id; state.draft = null; editing = false; savedOnly = false; $('search').value = '';
    announce('Document saved. Your changes stay in this browser.');
  } else if (button.dataset.format) {
    const input = $('edit-text'), start = input.selectionStart, end = input.selectionEnd;
    const selection = input.value.slice(start, end) || 'text';
    const formats = {bold:`**${selection}**`, italic:`*${selection}*`, heading:`## ${selection}`, list:`- ${selection}`, quote:`> ${selection}`};
    const prefix = ['heading','list','quote'].includes(button.dataset.format) && start > 0 && input.value[start - 1] !== '\n' ? '\n' : '';
    input.setRangeText(prefix + formats[button.dataset.format], start, end, 'select');
    input.dispatchEvent(new Event('input')); input.focus(); return;
  } else return;
  persist(); render();
});
let folding = false;

// A temporary, inert copy lets the hinge move without reparenting live editors
// or readers. Keep their scroll offsets and form contents in the visual copy.
function deviceSnapshot() {
  const source = $('device');
  const copy = source.cloneNode(true);
  const originals = [source, ...source.querySelectorAll('*')];
  const copies = [copy, ...copy.querySelectorAll('*')];
  const offsets = [];
  originals.forEach((element, index) => {
    const target = copies[index];
    const style = getComputedStyle(element);
    target.style.cssText = Array.from(style, property => `${property}:${style.getPropertyValue(property)};`).join('');
    target.removeAttribute('id');
    if ('value' in element) target.value = element.value;
    offsets.push([target, element.scrollTop, element.scrollLeft]);
  });
  Object.assign(copy.style, {position:'absolute', left:'0', top:'0', margin:'0', transform:'none', visibility:'visible', boxShadow:'none'});
  copy.inert = true;
  copy.setAttribute('aria-hidden', 'true');
  return {element:copy, restoreScroll:() => offsets.forEach(([el, top, left]) => { el.scrollTop = top; el.scrollLeft = left; })};
}

async function foldPhone() {
  if (folding) return;
  captureScroll();
  const closing = !state.folded;
  const openLibrary = state.folded ? !state.reference : libraryOpen;
  const applyState = folded => {
    state.folded = folded;
    libraryOpen = folded ? false : openLibrary;
    layout();
  };
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    applyState(closing); persist(); return;
  }
  folding = true;
  $('fold').disabled = true;
  $('reset').disabled = true;
  const stage = document.querySelector('.stage');
  let scene;
  try {
    applyState(false);
    const openLeft = deviceSnapshot();
    const openRight = deviceSnapshot();
    const openScale = $('device').getBoundingClientRect().width / 991;
    applyState(true);
    const closed = deviceSnapshot();
    const closedScale = $('device').getBoundingClientRect().width / 490;
    applyState(closing);
    persist();

    scene = document.createElement('div');
    scene.className = 'fold-scene';
    scene.inert = true;
    scene.setAttribute('aria-hidden', 'true');
    renderHTML(scene, '<div class="fold-rig"><div class="fold-stationary"><div class="fold-shade"></div></div><div class="fold-wing"><div class="fold-face fold-inside"><div class="fold-glint"></div></div><div class="fold-face fold-outside"></div></div></div>');
    const rig = scene.querySelector('.fold-rig');
    const wing = scene.querySelector('.fold-wing');
    const stationary = scene.querySelector('.fold-stationary');
    stationary.prepend(openRight.element);
    openRight.element.style.left = '-495.5px';
    scene.querySelector('.fold-inside').prepend(openLeft.element);
    scene.querySelector('.fold-outside').append(closed.element);
    closed.element.style.transformOrigin = 'top left';
    closed.element.style.transform = 'scale(1.01122449, 1.00997151)';
    stage.append(scene);
    [openLeft, openRight, closed].forEach(snapshot => snapshot.restoreScroll());
    $('device').style.visibility = 'hidden';
    $('device').inert = true;
    stage.style.height = `${Math.max(709 * openScale, 702 * closedScale)}px`;

    const options = {duration:1050, easing:'cubic-bezier(.22,.7,.18,1)', fill:'both', direction:closing ? 'normal' : 'reverse'};
    const animations = [
      stage.animate([{height:`${709 * openScale}px`}, {height:`${702 * closedScale}px`}], options),
      wing.animate([{transform:'rotateY(0deg)'}, {transform:'rotateY(180deg)'}], options),
      rig.animate([
        {transform:`scale(${openScale}) translateX(0px) rotateZ(0deg)`},
        {transform:`scale(${openScale * .90}) translateX(0px) rotateZ(-.8deg)`, offset:.45},
        {transform:`scale(${closedScale * 490 / 495.5}) translateX(-247.75px) rotateZ(0deg)`}
      ], options),
      scene.querySelector('.fold-shade').animate([{opacity:0},{opacity:.48,offset:.5},{opacity:.08}],options),
      scene.querySelector('.fold-glint').animate([{opacity:0},{opacity:.55,offset:.45},{opacity:0}],options)
    ];
    try {
      await Promise.all(animations.map(animation => animation.finished));
    } finally {
      animations.forEach(animation => animation.cancel());
    }
  } finally {
    scene?.remove();
    $('device').style.visibility = '';
    $('device').inert = false;
    applyState(closing);
    persist();
    $('fold').disabled = false;
    $('reset').disabled = false;
    folding = false;
  }
}
$('fold').onclick = foldPhone;
$('library-toggle').onclick = () => { libraryOpen = !libraryOpen; layout(); };
$('search').oninput = renderList;
$('all').onclick = () => { savedOnly = false; renderList(); };
$('saved').onclick = () => { savedOnly = true; renderList(); };
$('document-tab').onclick = () => { referenceActive = false; layout(); };
$('reference-tab').onclick = () => { referenceActive = true; layout(); };
$('new').onclick = () => startEditor(true);
$('settings-open').onclick = () => $('settings').showModal();
$('theme').onchange = event => { state.theme = event.target.value; appearance(); persist(); };
$('font-size').oninput = event => { state.fontSize = Number(event.target.value); appearance(); persist(); };
$('reset').onclick = () => $('reset-dialog').showModal();
$('reset-dialog').addEventListener('close', () => {
  if ($('reset-dialog').returnValue !== 'reset') return;
  state = fresh(); editing = false; referenceActive = false; savedOnly = false; libraryOpen = true;
  scrollPositions.clear(); $('search').value = ''; persist(); render();
  document.querySelectorAll('.page').forEach(el => { el.scrollTop = 0; });
  announce('Sample workspace restored.');
});
let stageWidth = -1;
new ResizeObserver(([entry]) => {
  const width = entry.contentRect.width;
  // layout sets the stage height; only available-width changes need a rescale.
  if (width === stageWidth) return;
  stageWidth = width;
  layout();
}).observe(document.querySelector('.stage'));
libraryOpen = !state.folded;
render();
if (!storageAvailable) announce('Browser storage is unavailable. Changes last until this page closes.');
else if (state.draft) announce('You have an unfinished draft. Choose Edit or New document to resume.');

for (const [id, name] of Object.entries({'settings-open':'profile','library-toggle':'sidebar','back-library':'back',new:'edit','search-open':'search','pin-page':'split','save-page':state.saved.includes(state.selected)?'check':'save','edit-page':'edit','share-page':'share'})) {
  renderHTML($(id), icon(name)); $(id).title = $(id).getAttribute('aria-label');
}
$('back-library').onclick = () => { libraryOpen = !libraryOpen; layout(); };
$('search-open').onclick = () => { libraryOpen = true; layout(); $('search').focus(); };
$('pin-page').onclick = () => { if(editing) return; $('primary').querySelector('[data-action=pin]').click(); };
$('save-page').onclick = () => { if(editing) return; $('primary').querySelector('[data-action=save]').click(); };
$('edit-page').onclick = () => startEditor(false);
$('share-page').onclick = async () => {
  const current = doc(state.selected);
  try { await navigator.clipboard.writeText(`${current.title}\n\n${current.text}`); announce('Sample document copied to the clipboard.'); }
  catch { announce('Select the document text to copy it.'); }
};
