const _iconPaths = {
  'hash': '<path d="M9.5 3.5 7.5 20.5M16.5 3.5l-2 17M4 8.5h16.5M3.5 15.5H20"/>',
  'at': '<circle cx="12" cy="12" r="4"/><path d="M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-4 8"/>',
  'image': '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="2"/><path d="m20 17-5-5-10 8"/>',
  'file': '<path d="M14 2.5H7A2.5 2.5 0 0 0 4.5 5v14A2.5 2.5 0 0 0 7 21.5h10a2.5 2.5 0 0 0 2.5-2.5V8z"/><path d="M14 2.5V8h5.5M8.5 13h7M8.5 17h5"/>',
  'audio': '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
  'join': '<path d="M4 12h15M13 6l6 6-6 6"/>',
  'leave': '<path d="M20 12H5M11 6l-6 6 6 6"/>',
  'pin': '<path d="M9 3.5h6l-1 6 3.5 3.5v1.5h-11V13L10 9.5z"/><path d="M12 14.5v6"/>',
  'phone': '<path d="M6.5 3.5h3l1.5 4.5-2.2 1.4a11 11 0 0 0 5.8 5.8l1.4-2.2 4.5 1.5v3a2 2 0 0 1-2 2A16.5 16.5 0 0 1 4.5 5.5a2 2 0 0 1 2-2z"/>',
  'pencil': '<path d="M4 20h4.5L19.5 9a2.1 2.1 0 0 0-3-3L5.5 17v3z"/><path d="m15 7.5 3 3"/>',
  'boost': '<path d="M7 3.5h10l4 6-9 11-9-11z"/><path d="M3 9.5h18M12 20.5 9 9.5l3-6 3 6z"/>',
  'thread':
      '<path d="M4.5 5.5h15v10H10l-5.5 4z"/><path d="M8.5 9.5h7M8.5 12.5h4"/>',
  'forward':
      '<path d="m14 5 6.5 6.5L14 18"/><path d="M20 11.5H10a6 6 0 0 0-6 6v1"/>',
  'reply': '<path d="M10 5 3.5 11.5 10 18"/><path d="M4 11.5h9.5a7 7 0 0 1 7 7v.5"/>',
  'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/>',
  'moon': '<path d="M20 14.5A8.5 8.5 0 1 1 9.5 4a7 7 0 0 0 10.5 10.5z"/>',
  'stage': '<circle cx="12" cy="9" r="3.5"/><path d="M6 20.5a6 6 0 0 1 12 0M4.5 4.5a10 10 0 0 0 0 9M19.5 4.5a10 10 0 0 1 0 9"/>',
  'shield': '<path d="M12 3 4.5 6v5.5c0 4.5 3.2 8.2 7.5 9.5 4.3-1.3 7.5-5 7.5-9.5V6z"/><path d="m9 12 2 2 4-4"/>',
  'poll': '<path d="M4 20V10M10 20V4M16 20v-7M21 20H3"/>',
  'blocked': '<circle cx="12" cy="12" r="8.5"/><path d="m6 6 12 12"/>',
  'chevron-left': '<path d="m14.5 6-6 6 6 6"/>',
  'chevron-right': '<path d="m9.5 6 6 6-6 6"/>',
  'chevron-up': '<path d="m6 14.5 6-6 6 6"/>',
  'chevron-down': '<path d="m6 9.5 6 6 6-6"/>',
  'search': '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.4-4.4"/>',
  'close': '<path d="M6 6l12 12M18 6 6 18"/>',
  'external': '<path d="M14 4.5h5.5V10M19.5 4.5 11 13M10 6.5H6.5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V14"/>',
};

String icon(String name, {String cls = ''}) =>
    '<svg class="icon${cls.isEmpty ? '' : ' $cls'}" viewBox="0 0 24 24" '
    'aria-hidden="true">${_iconPaths[name] ?? ''}</svg>';

String fontFaces(String regular, String italic) {
  final faces = StringBuffer();
  if (regular.isNotEmpty) {
    faces.write(
      '@font-face{font-family:Figtree;font-style:normal;'
      'font-weight:300 900;font-display:swap;'
      'src:url(data:font/woff2;base64,$regular) format("woff2")}',
    );
  }
  if (italic.isNotEmpty) {
    faces.write(
      '@font-face{font-family:Figtree;font-style:italic;'
      'font-weight:300 900;font-display:swap;'
      'src:url(data:font/woff2;base64,$italic) format("woff2")}',
    );
  }
  return faces.toString();
}

const headScript = '''
(function(){try{var t=localStorage.getItem('backscroll-theme');if(t)document.documentElement.dataset.theme=t}catch(e){}
document.addEventListener('error',function(e){var t=e.target;if(t&&t.tagName==='IMG'&&t.classList.contains('emoji')){t.replaceWith(document.createTextNode(t.alt))}},true)})();
''';

const bodyScript = '''
(function(){
var root=document.documentElement;
var toggle=document.getElementById('theme-toggle');
if(toggle)toggle.addEventListener('click',function(){var next=root.dataset.theme==='light'?'dark':'light';root.dataset.theme=next;try{localStorage.setItem('backscroll-theme',next)}catch(e){}});
document.addEventListener('click',function(e){var s=e.target.closest('.spoiler:not(.revealed),.spoiler-media:not(.revealed)');if(s){s.classList.add('revealed');e.preventDefault()}});
function flash(m){if(m&&m.classList.contains('msg')){m.classList.remove('flash');void m.offsetWidth;m.classList.add('flash')}}
function jumped(){try{return document.getElementById(decodeURIComponent(location.hash.slice(1)))}catch(e){return null}}
window.addEventListener('hashchange',function(){flash(jumped())});
document.addEventListener('click',function(e){var a=e.target.closest('a[href]');if(a&&a.hash&&a.hash===location.hash&&a.pathname===location.pathname)flash(jumped())});
flash(jumped());
var pinned=document.querySelectorAll('.msg.pinned'),pinsButton=document.getElementById('pins-toggle'),pinsPanel=document.getElementById('pins-panel');
function showPins(open){pinsPanel.hidden=!open;pinsButton.setAttribute('aria-expanded',String(open))}
if(pinned.length&&pinsButton&&pinsPanel){
var pinList=pinsPanel.querySelector('.pins-list');
pinned.forEach(function(m){var item=document.createElement('div');item.className='pin-item';var head=m.querySelector('.author');if(head)item.appendChild(head.cloneNode(true));var text=document.createElement('div');text.className='pin-text';var content=m.querySelector('.body>.content');if(content)text.innerHTML=content.innerHTML;else{var t=m.querySelector('.embed-title,.embed-desc,.components .content,.file-info a');text.textContent=t?t.textContent:'Attachment'}item.appendChild(text);item.addEventListener('click',function(e){if(e.target.closest('a,.spoiler:not(.revealed)'))return;showPins(false);location.hash=m.id;m.scrollIntoView({block:'center'});flash(m)});pinList.appendChild(item)});
pinsButton.querySelector('.count').textContent=pinned.length;pinsButton.hidden=false;
pinsButton.addEventListener('click',function(){showPins(pinsPanel.hidden)});
document.addEventListener('click',function(e){if(!pinsPanel.hidden&&!e.target.closest('#pins-panel,#pins-toggle'))showPins(false)});
document.addEventListener('keydown',function(e){if(e.key==='Escape'&&!pinsPanel.hidden)showPins(false)});
}
var findBar=document.getElementById('find-bar'),findInput=document.getElementById('find-input'),findCount=document.getElementById('find-count'),chat=document.querySelector('main.chat'),marks=[],current=-1,findTimer;
function clearMarks(){marks.forEach(function(m){var p=m.parentNode;if(p){p.replaceChild(document.createTextNode(m.textContent),m);p.normalize()}});marks=[];current=-1}
function showMatch(i){if(current>=0)marks[current].classList.remove('current');current=i;if(!marks.length){findCount.textContent=findInput.value.trim()?'No results':'';return}var m=marks[i];m.classList.add('current');var s=m.closest('.spoiler:not(.revealed)');if(s)s.classList.add('revealed');m.scrollIntoView({block:'center'});findCount.textContent=(i+1)+' of '+marks.length+(marks.length>=5000?'+':'')}
function runFind(){clearMarks();var q=findInput.value.trim().toLowerCase();if(q){var walker=document.createTreeWalker(chat,NodeFilter.SHOW_TEXT,{acceptNode:function(n){var p=n.parentNode;return n.nodeValue.toLowerCase().indexOf(q)<0||!p.closest('.msg')||p.closest('.side')?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT}}),nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);for(var n=0;n<nodes.length&&marks.length<5000;n++){var node=nodes[n],text=node.nodeValue,lower=text.toLowerCase(),at=0,i,frag=document.createDocumentFragment();while((i=lower.indexOf(q,at))>=0&&marks.length<5000){frag.appendChild(document.createTextNode(text.slice(at,i)));var m=document.createElement('mark');m.className='find';m.textContent=text.slice(i,i+q.length);frag.appendChild(m);marks.push(m);at=i+q.length}frag.appendChild(document.createTextNode(text.slice(at)));node.parentNode.replaceChild(frag,node)}}showMatch(0)}
function step(d){if(marks.length)showMatch((current+d+marks.length)%marks.length)}
function showFind(open){findBar.hidden=!open;if(open){findInput.focus();findInput.select()}else{clearTimeout(findTimer);findTimer=null;clearMarks();findInput.value='';findCount.textContent=''}}
if(findBar&&chat){
document.getElementById('find-toggle').addEventListener('click',function(){showFind(findBar.hidden)});
document.getElementById('find-close').addEventListener('click',function(){showFind(false)});
document.getElementById('find-prev').addEventListener('click',function(){step(-1)});
document.getElementById('find-next').addEventListener('click',function(){step(1)});
findInput.addEventListener('input',function(){clearTimeout(findTimer);findTimer=setTimeout(function(){findTimer=null;runFind()},250)});
findInput.addEventListener('keydown',function(e){if(e.key==='Enter'){e.preventDefault();if(findTimer){clearTimeout(findTimer);findTimer=null;runFind()}else step(e.shiftKey?-1:1)}else if(e.key==='Escape')showFind(false)});
}
function load(src,done){var s=document.createElement('script');s.src=src;s.async=true;s.onload=done;document.head.appendChild(s)}
var code=document.querySelectorAll('pre code[class*="language-"]');
if(code.length)load('https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js',function(){window.hljs.configure({ignoreUnescapedHTML:true});code.forEach(function(el){try{window.hljs.highlightElement(el)}catch(e){}})});
var stickers=document.querySelectorAll('.lottie[data-src]');
if(stickers.length)load('https://cdnjs.cloudflare.com/ajax/libs/lottie-web/5.12.2/lottie.min.js',function(){stickers.forEach(function(el){window.lottie.loadAnimation({container:el,path:el.dataset.src,renderer:'svg',loop:true,autoplay:true})})});
})();
''';

const css = '''
:root{--bg:#323339;--bg-2:#393a41;--bg-3:#2c2d32;--hover:rgba(151,151,159,.12);--accent:rgba(151,151,159,.16);--input:rgba(0,0,0,.08);--text:#f3f3f4;--strong:#fff;--subtle:#c5c6ca;--muted:#abacb2;--faint:#9d9ea5;--link:#76aff6;--line:rgba(151,151,159,.12);--edge:rgba(151,151,159,.2);--mention:rgba(88,101,242,.24);--mention-text:#cdd7ff;--code:rgba(88,101,242,.08);--code-text:#fff;--quote:#595a63;--spoiler:#7d7e87;--target:rgba(88,101,242,.16);--shadow:rgba(0,0,0,.24);--scroll:#767780;--hl-comment:#b3b3b9;--hl-keyword:#ffbdb9;--hl-string:#96dda9;--hl-number:#fcc0a1;--hl-operator:#ffcfcd;--hl-title:#bccaff;--hl-type:#ffb6ed;--hl-attr:#abcfff;--hl-meta:#ffc252;--hl-property:#8edae1;color-scheme:dark}
[data-theme=light]{--bg:#fbfbfb;--bg-2:#fff;--bg-3:#f3f3f4;--input:rgba(0,0,0,.02);--text:#2e2e34;--strong:#28282d;--subtle:#595a63;--muted:#6c6d76;--faint:#70717a;--link:#006dd4;--line:rgba(151,151,159,.28);--edge:rgba(151,151,159,.4);--mention-text:#2e3c88;--code:rgba(88,101,242,.04);--code-text:#36373e;--quote:#c5c6ca;--spoiler:#8f9097;--shadow:rgba(0,0,0,.12);--scroll:#8b8c94;--hl-comment:#696a73;--hl-keyword:#a9232e;--hl-string:#006734;--hl-number:#963b03;--hl-operator:#971d28;--hl-title:#404eb1;--hl-type:#9b277e;--hl-attr:#0158ab;--hl-meta:#884800;--hl-property:#00636e;color-scheme:light}
*{box-sizing:border-box}
[hidden]{display:none!important}
html{background:var(--bg)}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.375 Figtree,"Noto Sans","Helvetica Neue",Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility;--mono:Consolas,"Andale Mono WT","Andale Mono","Lucida Console","DejaVu Sans Mono","Liberation Mono",Menlo,Monaco,"Courier New",monospace}
@media (hover:hover) and (pointer:fine){::-webkit-scrollbar{width:16px;height:16px}::-webkit-scrollbar-corner{background:transparent}::-webkit-scrollbar-thumb{visibility:hidden;min-height:40px;border:4px solid transparent;border-radius:8px;background-color:var(--scroll);background-clip:padding-box}:hover::-webkit-scrollbar-thumb{visibility:visible}}
@supports not selector(::-webkit-scrollbar){html{scrollbar-color:var(--scroll) transparent}}
a{color:var(--link);text-decoration:none}
a:hover{text-decoration:underline}
.icon{width:1em;height:1em;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;flex:none}
.topbar{position:sticky;top:0;z-index:5;display:flex;align-items:center;justify-content:space-between;gap:12px;height:48px;padding:0 8px 0 16px;background:var(--bg);box-shadow:0 1px 0 var(--line)}
.topbar-title{display:flex;align-items:center;gap:8px;min-width:0;font-weight:600;color:var(--strong)}
.topbar-title .icon{width:24px;height:24px;color:var(--faint)}
.topbar-title .name-text{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.topic{min-width:0;margin-left:4px;padding-left:12px;border-left:1px solid var(--line);color:var(--muted);font-size:14px;font-weight:400;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.topbar-actions{display:flex;align-items:center;gap:4px;flex:none}
.topbar-actions a,.topbar-actions button{display:inline-flex;align-items:center;gap:6px;height:32px;padding:0 8px;border:0;border-radius:8px;background:none;color:var(--muted);font:inherit;font-size:14px;font-weight:500;cursor:pointer}
.topbar-actions a:hover,.topbar-actions button:hover{background:var(--accent);color:var(--strong);text-decoration:none}
.topbar-actions .icon{width:20px;height:20px}
[data-theme=light] .show-dark,:root:not([data-theme=light]) .show-light{display:none}
.chat{padding-bottom:16px}
.intro{margin:16px 16px 0;padding:16px 0 8px}
.intro-icon{display:flex;align-items:center;justify-content:center;width:68px;height:68px;margin-bottom:8px;border-radius:50%;background:var(--accent);color:var(--strong);overflow:hidden}
.intro-icon img{width:100%;height:100%;object-fit:cover}
.intro-icon .icon{width:42px;height:42px}
.intro h1{margin:8px 0;font-size:32px;line-height:40px;font-weight:800;color:var(--strong)}
.intro p{margin:0;color:var(--muted)}
.intro-meta{display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:12px;font-size:14px;color:var(--muted)}
.intro-meta a{font-weight:500}
.empty{margin:24px 16px;color:var(--muted)}
.divider{display:flex;align-items:center;gap:4px;margin:24px 16px 8px;color:var(--muted);font-size:12px;font-weight:600;line-height:13px}
.divider::before,.divider::after{content:"";flex:1;height:1px;background:var(--line)}
.group{margin-top:17px}
.msg{position:relative;min-height:22px;padding:2px 48px 2px 72px;overflow-wrap:anywhere;scroll-margin-top:64px}
.msg:hover{background:var(--hover)}
.msg.first{min-height:44px}
.msg.flash{animation:flash 2.6s ease-out}
@keyframes flash{0%,77%{background-color:var(--target);box-shadow:inset 2px 0 0 #5865f2}}
.avatar{position:absolute;left:16px;top:4px;width:40px;height:40px;border-radius:50%;object-fit:cover;background:var(--bg-2)}
.has-reply>.avatar{top:26px}
.author{margin:0;font-size:16px;line-height:22px;font-weight:500}
.name{color:var(--strong);font-weight:500}
.badge{display:inline-block;height:15px;margin-left:4px;padding:0 4px;border-radius:4px;background:#5865f2;color:#fff;font-size:10px;font-weight:600;line-height:15px;vertical-align:2px}
.author time,.system time{margin-left:4px;color:var(--faint);font-size:12px;font-weight:400}
.pin-mark{display:inline-flex;margin-left:6px;color:var(--muted);vertical-align:-2px}
.pin-mark .icon{width:14px;height:14px}
.topbar-actions .count{font-size:13px;font-weight:600}
.find-bar{position:sticky;top:48px;z-index:4;display:flex;align-items:center;gap:4px;padding:8px 8px 8px 16px;background:var(--bg);box-shadow:0 1px 0 var(--line)}
.find-bar input{flex:1;min-width:0;height:32px;padding:0 10px;border:1px solid var(--edge);border-radius:8px;background:var(--input);color:var(--text);font:inherit;font-size:14px;outline:none}
.find-bar input:focus{border-color:#5865f2}
.find-count{min-width:72px;padding:0 4px;color:var(--muted);font-size:13px;text-align:right;white-space:nowrap}
.find-bar button{display:inline-flex;align-items:center;justify-content:center;width:32px;height:32px;border:0;border-radius:8px;background:none;color:var(--muted);cursor:pointer}
.find-bar button:hover{background:var(--accent);color:var(--strong)}
.find-bar .icon{width:18px;height:18px}
mark.find{border-radius:2px;background:rgba(240,178,50,.35);color:inherit}
mark.find.current{background:#f0b232;color:#060607}
.pins-panel{position:absolute;top:44px;right:8px;z-index:6;width:min(440px,calc(100vw - 16px));max-height:min(640px,calc(100vh - 64px));overflow:auto;border-radius:8px;background:var(--bg-2);box-shadow:0 0 0 1px var(--line),0 8px 24px var(--shadow)}
.pins-head{position:sticky;top:0;z-index:1;padding:12px 16px;background:var(--bg-2);box-shadow:0 1px 0 var(--line);color:var(--strong);font-weight:600}
.pins-list{display:flex;flex-direction:column;gap:8px;padding:8px}
.pin-item{padding:8px 12px;border:1px solid var(--line);border-radius:8px;background:var(--bg);cursor:pointer;overflow-wrap:anywhere}
.pin-item:hover{background:var(--hover)}
.pin-item .pin-mark{display:none}
.pin-text{max-height:88px;overflow:hidden;font-size:14px;line-height:22px;white-space:pre-wrap}
.side{position:absolute;left:0;width:56px;padding-right:2px;color:var(--faint);font-size:11px;line-height:22px;text-align:right;visibility:hidden}
.msg:hover .side{visibility:visible}
.content{white-space:pre-wrap;line-height:22px}
.edited{margin-left:4px;color:var(--faint);font-size:10px;white-space:nowrap}
.emoji{width:22px;height:22px;margin:0 1px;object-fit:contain;vertical-align:-5px}
.emoji.jumbo{width:48px;height:48px;min-height:48px;vertical-align:-14px}
.mention{padding:0 2px;border-radius:3px;background:var(--mention);color:var(--mention-text);font-weight:500}
.mention:hover{background:#5865f2;color:#fff}
.timestamp-mention{padding:0 2px;border-radius:3px;background:var(--hover)}
code.inline{margin:-.2em 0;padding:.2em;border-radius:4px;background:var(--code);border:1px solid var(--edge);font-family:var(--mono);font-size:85%;white-space:pre-wrap}
pre.codeblock{max-width:90%;margin:6px 0 0;border:1px solid var(--edge);border-radius:4px;background:var(--code);overflow:auto}
pre.codeblock code{display:block;padding:7px;color:var(--code-text);font-family:var(--mono);font-size:14px;line-height:18px;white-space:pre-wrap}
blockquote{margin:0;padding:0 8px 0 12px;border-left:4px solid var(--quote);border-radius:4px}
.content h1,.content h2,.content h3{margin:8px 0 4px;color:var(--strong);font-weight:700;line-height:1.375}
.content h1{font-size:24px}.content h2{font-size:20px}.content h3{font-size:16px}
.subtext{display:block;color:var(--muted);font-size:13px;line-height:18px}
.content ul,.content ol{margin:4px 0;padding-left:24px;white-space:normal}
.content li{margin-bottom:4px;white-space:pre-wrap}
.spoiler{border-radius:4px;background:var(--spoiler);color:transparent;cursor:pointer}
.spoiler *{visibility:hidden}
.spoiler.revealed{background:var(--hover);color:inherit;cursor:auto}
.spoiler.revealed *{visibility:visible}
.attachments,.embeds,.stickers{display:flex;flex-direction:column;align-items:flex-start;gap:4px;padding-top:2px}
.media{position:relative;display:inline-block;max-width:min(550px,100%);border-radius:8px;overflow:hidden;line-height:0}
.media img,.media video{display:block;max-width:100%;height:auto;border-radius:8px;background:var(--bg-2)}
.spoiler-media{cursor:pointer}
.spoiler-media img,.spoiler-media video{filter:blur(44px)}
.spoiler-media::after{content:"SPOILER";position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);padding:8px 12px;border-radius:20px;background:rgba(0,0,0,.6);color:#fff;font-size:15px;font-weight:700;letter-spacing:.05em;line-height:1}
.spoiler-media.revealed{cursor:auto}
.spoiler-media.revealed img,.spoiler-media.revealed video{filter:none}
.spoiler-media.revealed::after{display:none}
.file{display:flex;flex-wrap:wrap;align-items:center;gap:8px;width:min(432px,100%);padding:10px;border:1px solid var(--line);border-radius:8px;background:var(--bg-2)}
.file>.icon{width:28px;height:36px;color:#5865f2;stroke-width:1.5}
.file-info{display:flex;flex:1;flex-direction:column;min-width:0}
.file-info a{overflow:hidden;font-size:16px;text-overflow:ellipsis;white-space:nowrap}
.file-size{color:var(--muted);font-size:12px}
.file audio{width:100%}
.embed{display:flex;gap:16px;max-width:min(520px,100%);padding:8px 16px 16px 12px;border-left:4px solid var(--quote);border-radius:4px;background:var(--bg-2);box-shadow:0 0 0 1px var(--line)}
.embed-main{display:flex;flex:1;flex-direction:column;gap:8px;min-width:0;padding-top:8px}
.embed-provider{color:var(--muted);font-size:12px}
.embed-author{display:flex;align-items:center;gap:8px;color:var(--strong);font-size:14px;font-weight:600}
.embed-author img{width:24px;height:24px;border-radius:50%;object-fit:cover}
.embed-author a{color:var(--strong)}
.embed-title{color:var(--strong);font-size:16px;font-weight:600}
.embed-desc{font-size:14px;line-height:18px;white-space:pre-wrap}
.embed-fields{display:grid;grid-template-columns:repeat(12,1fr);gap:8px}
.embed-field{min-width:0;font-size:14px;line-height:18px}
.field-name{margin-bottom:2px;color:var(--strong);font-weight:600}
.field-value{white-space:pre-wrap}
.embed-thumb{width:80px;height:80px;margin-top:8px;border-radius:4px;object-fit:contain;flex:none}
.embed-images{display:grid;grid-template-columns:1fr 1fr;gap:4px}
.embed-images.single{grid-template-columns:1fr}
.embed-images img{display:block;width:100%;max-height:300px;border-radius:4px;object-fit:cover}
.embed-images.single img{width:auto;max-width:100%;max-height:400px;object-fit:contain}
.embed-video{position:relative;display:block;border-radius:4px;overflow:hidden;line-height:0}
.embed-video img{width:100%}
.play{position:absolute;left:50%;top:50%;display:flex;align-items:center;justify-content:center;width:56px;height:56px;margin:-28px 0 0 -28px;border-radius:50%;background:rgba(0,0,0,.65);color:#fff}
.play::after{content:"";margin-left:5px;border-left:18px solid #fff;border-top:11px solid transparent;border-bottom:11px solid transparent}
.embed-footer{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:12px;font-weight:500}
.embed-footer img{width:20px;height:20px;border-radius:50%;object-fit:cover}
.sticker{width:160px;height:160px;object-fit:contain}
.components{display:flex;flex-direction:column;align-items:flex-start;gap:8px;padding-top:2px}
.container{position:relative;display:flex;flex-direction:column;align-items:flex-start;gap:8px;width:min(600px,100%);padding:16px;border:1px solid var(--line);border-radius:8px;background:var(--bg-2)}
.container.accent{padding-left:12px;border-left:4px solid var(--quote)}
.container.spoiler-media{overflow:hidden}
.container.spoiler-media>*{filter:blur(44px)}
.container.spoiler-media.revealed>*{filter:none}
.section{display:flex;align-items:flex-start;align-self:stretch;gap:12px}
.section-main{display:flex;flex:1;flex-direction:column;gap:4px;min-width:0}
.thumb{flex:none}
.thumb img{width:85px;height:85px;object-fit:cover}
.gallery{display:grid;grid-template-columns:repeat(2,1fr);gap:4px;width:min(550px,100%)}
.gallery.wide{grid-template-columns:repeat(3,1fr)}
.container .gallery{width:100%}
.gallery .media{max-width:none}
.gallery img,.gallery video{width:100%;aspect-ratio:1;object-fit:cover}
.sep{align-self:stretch;height:1px;background:var(--line)}
.sep.large{margin:8px 0}
.sep.blank{background:none}
.row{display:flex;flex-wrap:wrap;gap:8px;max-width:100%}
.button{display:inline-flex;align-items:center;justify-content:center;gap:6px;min-width:60px;min-height:32px;padding:2px 16px;border-radius:8px;background:var(--accent);color:var(--text);font-size:14px;font-weight:500;line-height:16px}
.button.primary{background:#5865f2;color:#fff}
.button.success{background:#008545;color:#fff}
.button.danger{background:#d22d39;color:#fff}
.button.disabled,.select.disabled{opacity:.5}
a.button:hover{background:var(--edge);text-decoration:none}
.button .emoji{width:18px;height:18px;margin:0;vertical-align:0}
.button .icon{width:16px;height:16px}
.select{display:flex;align-items:center;justify-content:space-between;gap:8px;width:400px;max-width:100%;min-height:40px;padding:8px 12px;border:1px solid var(--edge);border-radius:8px;background:var(--input);color:var(--muted);font-size:14px}
.select .icon{width:18px;height:18px}
.reactions{display:flex;flex-wrap:wrap;gap:4px;margin-top:4px}
.reaction{display:inline-flex;align-items:center;gap:6px;height:26px;padding:2px 6px;border:1px solid var(--line);border-radius:8px;background:var(--hover);color:var(--subtle);font-size:14px;font-weight:600}
.reaction .emoji{width:16px;height:16px;margin:0;vertical-align:0}
.reaction.burst{border-color:#ff73fa}
.reply{position:relative;display:flex;align-items:center;gap:4px;height:18px;margin-bottom:4px;color:var(--muted);font-size:14px;line-height:18px;white-space:nowrap}
.spine{position:absolute;left:-36px;top:8px;width:33px;height:12px;border:2px solid var(--quote);border-right:0;border-bottom:0;border-top-left-radius:6px}
.reply-avatar{width:16px;height:16px;border-radius:50%;object-fit:cover;flex:none}
.reply-name{flex:none;color:var(--strong);font-weight:500}
.reply-text{min-width:0;overflow:hidden;color:var(--muted);text-overflow:ellipsis}
a.reply-text:hover{color:var(--strong);text-decoration:none}
.reply .reply-text *{display:inline;margin:0;padding:0;border:0;font-size:inherit;white-space:nowrap}
.reply-text .emoji{width:16px;height:16px;vertical-align:-3px}
.reply .icon{width:16px;height:16px}
.reply .command{color:var(--link)}
.thread{display:flex;flex-direction:column;width:min(480px,100%);margin-top:4px;padding:8px 12px;border:1px solid var(--line);border-radius:8px;background:var(--bg-2);color:var(--text)}
a.thread:hover{background:var(--accent);text-decoration:none}
.thread-name{color:var(--strong);font-weight:600}
.thread-count{color:var(--link);font-size:14px;font-weight:600}
.forward{margin-top:2px;padding-left:12px;border-left:4px solid var(--quote);border-radius:4px}
.forward-label{display:flex;align-items:center;gap:4px;color:var(--muted);font-size:14px;font-style:italic}
.forward-meta{margin-top:2px;color:var(--muted);font-size:12px}
.poll{width:min(440px,100%);margin-top:4px;padding:16px;border:1px solid var(--line);border-radius:8px;background:var(--bg-2)}
.poll-question{color:var(--strong);font-size:17px;font-weight:600}
.poll-answer{position:relative;display:flex;justify-content:space-between;gap:12px;margin-top:8px;padding:10px 12px;border-radius:8px;background:var(--bg-3);overflow:hidden}
.poll-answer span{position:relative}
.poll-bar{position:absolute;top:0;bottom:0;left:0;background:rgba(88,101,242,.2)}
.poll-meta{margin-top:12px;color:var(--muted);font-size:14px}
.system{color:var(--muted);min-height:26px}
.system.first{min-height:26px}
.sys-icon{position:absolute;left:28px;top:5px;width:16px;height:16px;color:var(--muted)}
.sys-icon.join{color:#23a55a}.sys-icon.leave{color:#f23f43}.sys-icon.boost{color:#ff73fa}.sys-icon.pin,.sys-icon.thread{color:var(--muted)}
.system .name{cursor:default}
.system .body{line-height:22px}
.footer{display:flex;flex-wrap:wrap;align-items:center;gap:8px 16px;margin:24px 16px 32px;padding-top:12px;border-top:1px solid var(--line);color:var(--muted);font-size:13px}
.next-part{margin-left:auto;font-weight:600}
@media (max-width:640px){.msg{padding-right:12px}.topic{display:none}.intro h1{font-size:24px;line-height:30px}pre.codeblock{max-width:100%}}
.hljs-comment,.hljs-code,.hljs-formula{color:var(--hl-comment)}
.hljs-keyword,.hljs-doctag,.hljs-template-tag,.hljs-template-variable,.hljs-section,.hljs-deletion{color:var(--hl-keyword)}
.hljs-string,.hljs-regexp,.hljs-addition{color:var(--hl-string)}
.hljs-number{color:var(--hl-number)}
.hljs-operator{color:var(--hl-operator)}
.hljs-title{color:var(--hl-title)}
.hljs-type,.hljs-built_in,.hljs-name,.hljs-quote,.hljs-selector-tag,.hljs-selector-pseudo{color:var(--hl-type)}
.hljs-attr,.hljs-attribute,.hljs-bullet,.hljs-link{color:var(--hl-attr)}
.hljs-meta,.hljs-symbol{color:var(--hl-meta)}
.hljs-property{color:var(--hl-property)}
.hljs-addition{background:rgba(0,133,69,.12)}.hljs-deletion{background:rgba(210,45,57,.12)}
.hljs-emphasis{font-style:italic}.hljs-section,.hljs-strong{font-weight:700}.hljs-link{text-decoration:underline}
''';
