(() => {
'use strict';
const screens = window.DESIGN_SCREENS;
const byId = new Map(screens.map(s => [s.id, s]));
const screen = document.getElementById('screen');
const picker = document.getElementById('screen-picker');
const viewport = document.getElementById('viewport');
const win = document.getElementById('app-window');
const help = document.getElementById('help-dialog');
let helpTrigger = null, activeId = '', toastTimer;
const icons = {
wave:'<path d="M3 9v6M7 5v14M11 2v20M15 6v12M19 9v6M23 10v4"/>',
clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
book:'<path d="M5 3h14v18H5zM8 3v18M11 8h5M11 12h4"/>',
voice:'<path d="M4 9v6M8 5v14M12 2v20M16 5v14M20 9v6"/>',
chart:'<path d="M4 20h16M6 16V9M12 16V4M18 16v-5"/>',
settings:'<path d="M3 6h18M3 12h18M3 18h18"/><circle cx="8" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="10" cy="18" r="2"/>',
lock:'<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/>'
};
document.querySelectorAll('[data-icon]').forEach(n => n.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true">'+icons[n.dataset.icon]+'</svg>');
const groups = new Map();
for(const s of screens){ if(!groups.has(s.group))groups.set(s.group,[]); groups.get(s.group).push(s); }
for(const [name,list] of groups){const optgroup=document.createElement('optgroup');optgroup.label=name;for(const s of list){const o=document.createElement('option');o.value=s.id;o.textContent=s.title;optgroup.append(o);}picker.append(optgroup);}
function navFor(id){if(id==='text-lab'||id.startsWith('text-lab-')||id.startsWith('jev-')||id==='key-delete-confirm'||id.startsWith('settings')||['permissions','input-diagnostics','writing-profiles','context-apps','api-connection','jev-settings','jev-assistance','language-examples','expression-examples'].includes(id))return 'settings';if(id.startsWith('history')||id.startsWith('recovery'))return 'history';if(id.startsWith('dictionary'))return 'dictionary';if(id.startsWith('usage'))return 'usage';if(id.startsWith('model')||id.startsWith('speaker-')||id.startsWith('speech-lab')||id==='licenses')return 'models';return 'home';}
const navNames={home:'받아쓰기',history:'기록',dictionary:'개인 사전',models:'음성 모델',usage:'사용량',settings:'설정'};
function showToast(msg){const t=document.getElementById('toast');t.textContent=msg;t.hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>t.hidden=true,3000);}
function render(id,updateHash=true){const s=byId.get(id);if(!s){showToast('시안의 목적지 화면을 찾지 못했습니다: '+id);return false;}if(help.open)help.close();activeId=id;screen.innerHTML=s.html;picker.value=id;viewport.scrollTop=0;const nav=navFor(id);document.getElementById('context-title').textContent=navNames[nav];document.querySelectorAll('#main-nav [data-nav]').forEach(n=>{if(n.dataset.nav===nav)n.setAttribute('aria-current','page');else n.removeAttribute('aria-current');});
// Every help button stays readable even when its value control is disabled.
screen.querySelectorAll('[data-help]').forEach(n=>{n.type='button';n.textContent='?';if(!n.getAttribute('aria-label'))n.setAttribute('aria-label',(n.closest('.row')?.querySelector('.row-label')?.textContent.trim()||'항목')+' 도움말');n.setAttribute('aria-haspopup','dialog');n.disabled=false;});
screen.querySelectorAll('button').forEach(n=>n.type='button');
screen.querySelectorAll('input:not([type]),input[type=text],textarea').forEach(n=>{if(!n.getAttribute('aria-label')&&!n.labels?.length)n.setAttribute('aria-label',n.placeholder||'시안 입력');});
if(updateHash&&location.hash.slice(1)!==id)history.replaceState(null,'','#'+id);document.title='OpenNoType 재디자인 · '+s.title;return true;}
function openHelp(n){helpTrigger=n;const label=n.getAttribute('aria-label')||'항목 도움말';document.getElementById('help-title').textContent=label.replace(/\s*도움말$/,'');document.getElementById('help-body').textContent=n.dataset.help;help.showModal();document.getElementById('help-close').focus();}
document.addEventListener('click',e=>{const n=e.target.closest('[data-help],[data-go],[data-toast]');if(!n)return;if(n.dataset.help){e.preventDefault();openHelp(n);return;}if(n.dataset.go){if(render(n.dataset.go)){const title=screen.querySelector('h1');if(title){title.tabIndex=-1;title.focus({preventScroll:true});}else viewport.focus({preventScroll:true});}return;}if(n.dataset.toast)showToast(n.dataset.toast);});
document.addEventListener('submit',e=>{e.preventDefault();showToast('디자인 시안에서는 외부 전송하거나 저장하지 않습니다.');});
picker.addEventListener('change',()=>render(picker.value));
document.getElementById('theme-button').addEventListener('click',e=>{const isDark=document.documentElement.dataset.theme!=='dark';document.documentElement.dataset.theme=isDark?'dark':'light';e.currentTarget.textContent=isDark?'라이트 보기':'다크 보기';e.currentTarget.setAttribute('aria-pressed',isDark);});
document.getElementById('measure-button').addEventListener('click',e=>{const on=win.classList.toggle('measure');e.currentTarget.setAttribute('aria-pressed',on);e.currentTarget.textContent=on?'치수 숨기기':'치수 보기';});
document.getElementById('size-picker').addEventListener('change',e=>{const width=Number(e.target.value);document.documentElement.style.setProperty('--window-width',width+'px');document.documentElement.style.setProperty('--window-height',({960:680,1120:760,1440:900})[width]+'px');win.classList.toggle('screen-narrow',width===960);});
document.getElementById('help-close').addEventListener('click',()=>help.close());
help.addEventListener('click',e=>{if(e.target===help){const b=help.getBoundingClientRect();if(e.clientX<b.left||e.clientX>b.right||e.clientY<b.top||e.clientY>b.bottom)help.close();}});
help.addEventListener('close',()=>{if(helpTrigger?.isConnected)helpTrigger.focus();helpTrigger=null;});
window.addEventListener('hashchange',()=>render(location.hash.slice(1),false));
document.getElementById('screen-count').textContent='전체 '+screens.length+'개 화면·상태';
render(byId.has(location.hash.slice(1))?location.hash.slice(1):'settings-dictation');
// Exposed only for bounded offline review of this design artifact.
window.designReview={screens:screens.map(({id,title,group})=>({id,title,group})),navigate:render,get current(){return activeId;}};
})();
