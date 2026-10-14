/* 설정·모델 화면 시안. 앱·파일·API·실제 설정에 접근하지 않습니다. */
(() => {
  window.DESIGN_SCREENS = window.DESIGN_SCREENS || [];
  const memory = {
    processing: 'clean', language: 'original', expression: 'faithful', strength: 0,
    translationLanguage: 'en-US', refine: false, activation: 'toggle', mic: 'default',
    sound: false, mute: false, speechPlace: 'online', speechProvider: 'openAI',
    textProvider: 'shared', review: 'off', reviewProvider: 'openRouter', translationReview: false,
    model: 'large', unload: 'never', preview: false, speaker: false, history: true,
    retention: '30', usage: true, learning: true, login: false, appearance: 'system',
    interfaceLanguage: 'ko', automaticUpdates: true, detailed: false, economy: false,
    alternatives: false, clarify: false, reRecognition: false, errorLearning: false,
    exampleLanguage: 'original', exampleExpression: 'faithful', connectionTarget: 'speech',
    speechModel: 'default', textModel: 'default', improvementModel: 'default'
  };
  const entries = new Map();
  const renderers = new Map();
  const esc = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const help = (label, text) => `<button type="button" class="button quiet" data-help="${esc(text)}" aria-label="${esc(label)} 도움말" aria-haspopup="dialog">?</button>`;
  const go = (label, id, kind = '') => `<button class="button ${kind}" data-go="${id}">${label}</button>`;
  const connection = (label, target) => go(label,'api-connection','quiet').replace('data-go=',`data-b-target="${target}" data-go=`);
  const toast = (label, text, kind = '') => `<button class="button ${kind}" data-toast="${esc(text)}">${label}</button>`;
  const badge = (label, kind = '') => `<span class="badge ${kind}">${label}</span>`;
  const select = (key, items, disabled = false, width = 240) => `<select class="select" data-b-setting="${key}" aria-label="${({processing:'받아쓰기 처리',language:'받아쓰기 출력 언어',expression:'표현 방식',strength:'편집 강도',translationLanguage:'번역 단축키 언어',activation:'단축키 동작',mic:'녹음 마이크',speechPlace:'음성 인식 위치',speechProvider:'음성 인식 제공자',speechModel:'음성 모델',textModel:'문장 모델',improvementModel:'Jev 보조 모델',textProvider:'문장 제공자',review:'자동 검토',reviewProvider:'Jev 연결',model:'로컬 모델',unload:'메모리 유지',retention:'텍스트 보관 기간',appearance:'화면 모드',interfaceLanguage:'앱 언어',exampleLanguage:'미리 볼 언어',exampleExpression:'미리 볼 표현'})[key] || key}" style="width:${width}px;max-width:100%" ${disabled?'disabled':''}>${items.map(([value,label])=>`<option value="${value}" ${String(memory[key])===value?'selected':''}>${label}</option>`).join('')}</select>`;
  const toggle = (key, label, disabled = false) => `<input class="switch" type="checkbox" data-b-setting="${key}" aria-label="${label}" ${memory[key]?'checked':''} ${disabled?'disabled':''}>`;
  const row = (label, value, description, status = '') => `<div class="row"><div class="row-label"><span>${label}${description?help(label,description):''}</span>${status?`<span class="caption muted">${status}</span>`:''}</div><div class="row-value">${value}</div></div>`;
  const panel = (title, rows, controls = '') => `<section class="panel"><div class="panel-head"><h2>${title}</h2>${controls}</div>${rows}</section>`;
  const head = (title, eyebrow = '설정', controls = '') => `<header class="page-head"><div class="panel-head"><div>${eyebrow?`<span class="eyebrow">${eyebrow}</span>`:''}<h1>${title}</h1></div>${controls?`<div class="toolbar">${controls}</div>`:''}</div></header>`;
  const navItems = [['settings-dictation','받아쓰기'],['settings-recording','녹음·단축키'],['settings-connections','AI 연결'],['settings-privacy','개인정보'],['settings-general','앱 관리'],['settings-advanced','고급 도구']];
  const tabs = active => `<nav class="tabs" aria-label="설정 분류">${navItems.map(([id,label])=>`<button class="tab ${id===active?'active':''}" data-go="${id}" ${id===active?'aria-current="page"':''}>${label}</button>`).join('')}</nav>`;
  const shell = (id, title, contents, settings = false, controls = '') => `<div class="stack" data-b-screen="${id}">${head(title, settings?'':'설정 · 상세',controls)}${settings?tabs(id):''}${contents}</div>`;
  const langs = [['original','말한 언어 유지'],['en-US','영어 · 미국식'],['en-GB','영어 · 영국식'],['ko','한국어'],['ja','일본어'],['zh-Hans','중국어 · 간체'],['zh-Hant','중국어 · 번체']];
  const expressions = [['faithful','현재 받아쓰기'],['concise','간결하게'],['summary','핵심 요약'],['clear','명확하게'],['expanded','자세하게'],['creative','창의적으로']];
  const providers = [['openAI','OpenAI'],['groq','Groq'],['openRouter','OpenRouter'],['anthropic','Anthropic']];
  const modes = [['off','사용 안 함'],['observe','입력 후 검토'],['protect','입력 전 확인'],['repair','입력 전 검토·교정']];
  const translation = () => memory.language !== 'original';
  const fast = () => memory.processing === 'fast' && !translation();
  const local = () => fast() || memory.speechPlace === 'local' || memory.speechProvider === 'anthropic';
  const modelTitle = () => ({large:'Whisper Large v3',small:'Whisper Small',base:'Whisper Base'})[memory.model];
  const inactiveExpression = () => fast() || translation();
  const effective = () => translation() ? `${langs.find(x=>x[0]===memory.language)[1]}로 번역 · AI 처리` : fast() ? '말한 언어 유지 · 이 Mac · 정리 없이 입력' : '말한 언어 유지 · 문장 정리 후 입력';
  const reviewStatus = () => fast() ? '현재 미적용 · 빠른 로컬 받아쓰기' : translation() ? '일반 받아쓰기 검토 미적용 · 번역 검토 별도' : ({off:'자동 검토 꺼짐',observe:memory.reRecognition?'재인식으로 입력 전 대기 가능':'입력 후 검토 · 입력한 글은 유지',protect:'위험 신호 시 보류 · 검토 실패 시 기존 결과 입력',repair:'검토·교정 실패 또는 미해결 시 입력 보류'})[memory.review];
  const helpText = {
    processing:'정리해서 입력은 인식한 문장을 AI로 정리합니다. 빠른 로컬 받아쓰기는 말한 언어 유지일 때 이 Mac의 인식문을 AI 정리·자동 Jev 없이 입력합니다. 로컬 모델 준비가 필요하며 이 경로는 음성·문장을 외부 AI로 보내지 않습니다. 번역·선택 문장 수정·프롬프트는 별도 AI 처리를 사용합니다. 인식문이 발화를 완벽히 복제한다는 뜻은 아닙니다.',
    language:'평소 받아쓰기 단축키의 출력 언어입니다. 말한 언어 유지와 번역 중 선택합니다. 별도 번역 단축키 언어와 독립적으로 저장됩니다. 번역 중에는 표현 방식과 빠른 로컬 처리가 적용되지 않으며 저장값은 유지됩니다. 예시를 보기만 해서는 설정이 바뀌지 않습니다.',
    expression:'말한 언어를 유지하면서 AI로 정리하는 받아쓰기에만 적용합니다. 현재 받아쓰기는 기존 말실수·반복 정리 방식입니다. 요약은 압축, 자세하게는 발화 안의 연결을 풀어 쓰는 방향입니다. 숫자·이름·조건·부정·의도는 유지하도록 요청합니다. 번역·선택 수정·빠른 로컬에는 미적용이며 저장한 선택은 유지됩니다.',
    strength:'선택한 표현 방향으로 편집하는 정도입니다. 인식 정확도·모델을 바꾸는 값이 아닙니다. 현재 받아쓰기 또는 강도 0은 기존 정리를 유지하며 AI 정리 전체를 끄지 않습니다. 다른 표현을 강도 0에서 선택하면 기존 정책대로 40으로 시작합니다.',
    refine:'받아쓰기 번역과 별도 번역의 초안을 한 번 더 다듬습니다. 원문·초안·목표 언어·말투·사전 힌트를 현재 문장 서비스로 추가 전송합니다. 시간·비용이 늘 수 있고 실패하면 원문이나 초안을 대신 자동 입력하지 않고 보류합니다. Jev 검토와 독립입니다.',
    review:'자동 검토는 사용 안 함 / 입력 후 검토 / 입력 전 확인 / 입력 전 검토·교정으로 구별합니다. 입력 후 검토는 이미 입력한 글을 바꾸지 않으며 음성 재인식이 켜져 있으면 입력 전 대기가 생길 수 있습니다. 입력 전 확인은 위험 신호에 보류하지만 일반 검토 실패·시간 초과에는 기존 결과를 입력합니다. 입력 전 교정은 최대 한 번 교정·재검토하고 실패·미해결이면 보류합니다. 원문·결과·표기 후보를 Jev로 전송하고 비용이 추가됩니다.',
    translationReview:'입력 전 확인과 이 옵션을 함께 켰을 때 번역도 입력 전에 검토합니다. 원문·번역·목표 언어·말투를 추가 전송합니다. 일반 받아쓰기 입력 전 확인과 달리 번역 검토 실패·미확인에도 입력을 보류하며 번역을 자동 교정하지 않습니다.',
    profiles:'녹음을 시작한 앱에 맞는 작성 형식·말투입니다. 따로 지정하지 않은 앱에서는 말한 반말·존댓말을 유지합니다. 브라우저 사이트·대화 상대를 판단하거나 주변 문맥을 자동으로 읽지 않습니다. 빠른 로컬은 미적용, 번역은 앱별 말투를 적용하며 프롬프트에는 적용하지 않습니다.',
    key:'서비스별 API 키는 Keychain에 명시적으로 저장합니다. 키 저장과 실제 서비스 연결 성공은 다릅니다. 제공자별 기존 키·모델은 유지하며 다른 서비스로 자동 복사하지 않습니다. 이 시안에 실제 키를 입력하지 마세요.',
    history:'결과·원문은 이 Mac에 암호화해 보관합니다. 기록을 끄면 진행 중 검토·진단·Jev 오류 유형을 지우고 기존 텍스트 기록은 보관 기간을 따릅니다. 개인 사전은 유지됩니다. 성공 원음은 삭제하고 실패 원음은 별도 24시간 복구 정책을 따릅니다.',
    learning:'입력이 확인된 받아쓰기에서 같은 입력창의 대소문자·일부 고유명사 철자처럼 안전한 교정만 자동 학습합니다. 확인이 필요한 변경은 후보로 제안합니다. 수치·버전·날짜·문장 전체는 자동 등록하지 않습니다. 끄면 새 관찰을 멈추며 기존 사전은 유지됩니다.',
    preview:'로컬 인식에서 최근 12초를 반복 인식하는 실험입니다. 확정 결과는 전체 녹음을 다시 인식합니다. 추가 연산이 필요하며 내 목소리 필터가 켜지면 미리보기는 일시 미적용입니다.',
    speaker:'등록한 목소리의 단독 발화 구간을 찾는 실험 기능입니다. 화자 모델 준비와 목소리 등록이 필요합니다. 실제 사용자·TV·겹말 환경 성능 검증 전이며 기본 꺼짐입니다. 등록 원음은 삭제하고 특징만 암호화합니다.'
  };
  function add(id, title, renderer, group='설정') {
    const entry = {id,title,group,html:renderer()};
    entries.set(id,entry); renderers.set(id,renderer); window.DESIGN_SCREENS.push(entry);
  }
  function refresh(element, key='') {
    for (const [id,entry] of entries) entry.html = renderers.get(id)();
    const region = element?.closest('[data-b-screen]');
    if (!region || !renderers.has(region.dataset.bScreen)) return;
    const id = region.dataset.bScreen;
    region.outerHTML = entries.get(id).html;
    if (key) document.querySelector(`[data-b-screen="${id}"] [data-b-setting="${key}"]`)?.focus();
  }
  add('settings-dictation','받아쓰기 설정',()=>shell('settings-dictation','받아쓰기',
    `<section class="panel"><h2 class="settings-group-heading">입력 방식</h2>`+row('받아쓰기 처리',select('processing',[['clean','정리해서 입력'],['fast','빠른 로컬 받아쓰기']]),helpText.processing,memory.processing==='fast'&&translation()?'현재 미적용 · 번역은 AI 처리':'')+
      row('출력 언어',select('language',langs,false,168)+go('예시','language-examples','quiet'),helpText.language)+
      row('로컬 모델',go(modelTitle(),'model-detail','quiet'),helpText.processing,fast()?'이 Mac에서 인식':'')+
    `<h2 class="settings-group-heading">문장과 말투</h2>`+row('표현 방식',select('expression',expressions,inactiveExpression(),168)+go('예시','expression-examples','quiet'),helpText.expression,inactiveExpression()?'현재 미적용 · 선택값은 유지':'')+
      row('AI 편집 강도',`<span style="display:flex;align-items:center;gap:8px;width:240px;max-width:100%;flex-wrap:nowrap"><input style="flex:1;min-width:0" aria-label="AI 편집 강도" type="range" min="0" max="100" step="5" value="${memory.strength}" data-b-setting="strength" ${inactiveExpression()||memory.expression==='faithful'?'disabled':''}><span class="utility-number">${memory.strength}</span></span>`,helpText.strength)+
      row('앱별 작성 방식',go('앱별 설정','writing-profiles','quiet'),helpText.profiles,fast()?'현재 미적용 · 빠른 로컬 받아쓰기':translation()?'앱별 말투만 번역에 적용':'')+
    `<h2 class="settings-group-heading">번역과 검토</h2>`+row('번역 단축키 언어',select('translationLanguage',langs.filter(x=>x[0]!=='original')),helpText.language)+
      row('번역 문장 다듬기',toggle('refine','번역 문장 다듬기'),helpText.refine,memory.refine?'실험 · 추가 요청 1회 · 실패 시 보류':'')+
      row('자동 문장 검토',go(modes.find(x=>x[0]===memory.review)[1],'jev-settings','quiet'),helpText.review,memory.review==='off'&&!fast()&&!translation()?'':reviewStatus())+'</section>',true));
  add('settings-recording','녹음·단축키',()=>shell('settings-recording','녹음·단축키',
    panel('녹음',row('녹음 마이크',select('mic',[['default','시스템 기본 마이크'],['internal','Mac 내장 마이크'],['missing','지정 마이크 연결 끊김']],false,200)+toast('↻','마이크 목록 새로고침 시안입니다. 실제 장치를 조회하지 않습니다.','quiet'),'시스템 기본 또는 지정 마이크를 선택합니다. 지정 장치 분리는 오류로 표시하며 시스템 기본 입력을 바꾸지 않습니다.',memory.mic==='missing'?'선택한 마이크 연결 끊김':'')+
      row('단축키 동작',select('activation',[['toggle','한 번 눌러 시작·종료'],['hold','누르는 동안 녹음'],['mixed','짧게 또는 길게 누르기']]),'한 번 누르기는 다음 누름까지 녹음합니다. 길게 누르기는 키를 떼면 끝냅니다. 혼합은 짧게 누르면 계속 녹음하고 길게 누르면 떼는 순간 끝납니다.')+
      row('준비·종료 알림음',toggle('sound','준비·종료 알림음'),'실제 음성을 받을 준비가 됐을 때와 종료 때 소리를 냅니다. 시스템 음소거와 함께 쓰면 들리지 않을 수 있습니다.',memory.sound&&memory.mute?'음소거로 준비 알림음이 들리지 않을 수 있음':'')+
      row('녹음 중 시스템 음소거',toggle('mute','녹음 중 시스템 음소거'),'끝나면 이전 상태로 복원하며 녹음 중 사용자가 직접 바꾼 값은 존중합니다.'))+
    panel('작업별 단축키',[['받아쓰기','⌥ Space'],['번역','⌥ ⇧ Space'],['선택 문장 수정','⌃ ⌥ Space'],['프롬프트 만들기','⌃ ⌥ ⇧ Space']].map(([label,key])=>row(label,`<kbd class="shortcut">${key}</kbd>${toast('변경','새 단축키 입력 화면 시안입니다. 실제 단축키는 바꾸지 않습니다.','quiet')}`,'Option·Control·Command를 포함한 조합을 사용합니다. 중복과 다른 앱 충돌을 확인합니다.')).join(''),go('충돌 확인','input-diagnostics','quiet')),true));
  add('settings-connections','AI 연결',()=>shell('settings-connections','AI 연결',
    panel('음성 인식',row('인식 위치',select('speechPlace',[['online','온라인으로 인식'],['local','이 Mac에서 인식']],memory.speechProvider==='anthropic'),'로컬 인식과 문장 정리는 독립입니다. Anthropic은 로컬 음성 인식을 사용합니다. 빠른 로컬 받아쓰기는 원래 언어일 때 인식·문장 모두 이 Mac에서 처리합니다.',fast()?'받아쓰기는 빠른 로컬로 처리':memory.speechProvider==='anthropic'?'Anthropic 선택 · 음성 인식은 이 Mac':'')+
      row('음성 제공자',select('speechProvider',providers),'음성 인식 제공자의 기존 키·모델을 선택합니다. 제공자별 저장값은 유지됩니다.')+
      row('음성 연결·모델',local()?go('로컬 모델 관리','models','quiet'):connection('연결 관리','speech'),helpText.key,local()?'로컬 모델 선택과 준비는 별도':'녹음 외부 전송 · API 비용'))+
    panel('문장 처리',row('문장 제공자',select('textProvider',[['shared','음성 제공자 재사용'],...providers]),'받아쓰기 정리·번역·선택 수정에 사용합니다. 음성과 같은 제공자이면 기존 키 공유 조건을 유지합니다.',fast()?'현재 받아쓰기에는 미적용':'인식문·요청 외부 전송')+
      row('API 키·모델',connection('연결 관리','text'),helpText.key))+
    panel('검토와 비용',row('문장 검토 연결',go('Jev 연결·검토','jev-settings','quiet'),helpText.review)+
      row('모델별 사용량',go('사용량·비용','usage','quiet'),'음성·문장·로컬 사용량을 구별하며 내용과 원음을 통계에 저장하지 않습니다.')),true));
  add('settings-privacy','개인정보',()=>shell('settings-privacy','개인정보',
    panel('기록과 보관',row('처리 결과 기록',toggle('history','처리 결과 기록'),helpText.history,!memory.history?'새 기록 저장 안 함 · 기존 기록은 보관 정책 유지':'')+
      row('텍스트 보관 기간',select('retention',[['1','1일'],['7','7일'],['30','30일'],['90','90일'],['forever','계속 보관']]),'텍스트 보관 기간입니다. 실패 원음의 24시간 복구와 별도이며 손상된 보관 설정은 임의 삭제로 바꾸지 않습니다.')+
      row('실패 녹음',badge('24시간 · 암호화')+go('확인','recovery','quiet'),helpText.history))+
    panel('전송과 문맥',row('현재 받아쓰기 전송',badge(fast()?'외부 전송 없음':'문장 또는 녹음 전송',fast()?'success':'warn'),helpText.processing)+
      row('앱별 주변 문맥',go('허용한 앱 없음','context-apps','quiet'),'허용한 앱에서만 커서 앞 최대 1,000자를 AI에 함께 보냅니다. 보안 입력란은 제외하고 문맥은 보관하지 않습니다. 앱별 문체와 독립입니다.')+
      row('추가 전송 설정',go('실험·검토 확인','settings-advanced','quiet'),helpText.refine,memory.refine||memory.review!=='off'?'추가 요청 설정 켜짐':''))+
    panel('학습과 통계',row('고친 표기 기억하기',go('개인 사전에서 관리','dictionary','quiet'),helpText.learning)+
      row('사용량 기록',toggle('usage','사용량 기록'),'요청·모델·토큰·처리 시간만 암호화해 최대 10,000건 보관합니다. 끄면 새 수집을 멈추고 기존 통계는 유지합니다.')+
      row('보관한 통계',go('사용량 보기','usage','quiet'),'텍스트 기록과 별도이며 통계 삭제는 사용량 화면에서 확인 후 수행합니다.')),true));
  add('settings-general','앱 관리',()=>shell('settings-general','앱 관리',
    panel('앱과 화면',row('앱 언어',select('interfaceLanguage',[['ko','한국어'],['en','English']]),'인터페이스 언어만 즉시 바뀝니다. 인식·출력·번역 언어는 바뀌지 않습니다. 신규 설치의 기존 영어 기본값과 기존 한국어 설정을 보존합니다.')+
      row('화면 모드',select('appearance',[['system','시스템에 맞춤'],['light','라이트'],['dark','다크']]),'시스템·라이트·다크를 선택하며 기존 설정을 유지합니다.')+
      row('로그인할 때 실행',toggle('login','로그인할 때 실행'),'창 없이 메뉴바에서 대기합니다. 실제 등록 오류는 현재 상태로 표시합니다.')+
      row('로그인 항목 관리',toast('시스템 설정','로그인 항목 설정 진입 시안입니다. 실제 시스템 설정을 열지 않습니다.','quiet'),'실제 로그인 항목 등록 상태와 오류 안내를 유지합니다.')+
      row('로그인 항목',toast('시스템 설정','로그인 항목 시스템 설정 진입 시안입니다. 실제 시스템 설정은 열지 않습니다.','quiet'),'Mac의 로그인 항목에서 허용 상태를 확인합니다.'))+
    panel('업데이트',row('현재 버전',badge('0.2.9 (45)')+toast('업데이트 확인','업데이트 확인 화면 시안입니다. 네트워크 요청을 하지 않습니다.','quiet'),'커뮤니티 배포·Apple 공증 없음. 실제 업데이트는 검증된 공개 피드와 키를 사용합니다.')+
      row('새 버전 자동 확인',toggle('automaticUpdates','새 버전 자동 확인'),'새 버전을 알려 주며 자동 설치는 켜지 않습니다. 녹음·문장 처리 중 확인·설치 보호를 유지합니다.')+
      row('릴리스와 확인 시각',toast('GitHub 릴리스','릴리스 페이지 진입 시안입니다. 네트워크를 사용하지 않습니다.','quiet')+badge('아직 확인 전'),'기존 릴리스 링크와 마지막 확인 시각을 유지합니다.')+
      row('지연된 업데이트',badge('대기 없음'),'처리 중 설치가 보류되면 이유와 설치·재실행 버튼을 표시합니다.'))+
    panel('정보',row('모델·오픈소스 고지',go('라이선스','licenses','quiet'),'음성·화자 모델과 관련 라이브러리의 기존 라이선스·출처를 유지합니다.')),true));
  add('settings-advanced','고급 도구',()=>shell('settings-advanced','고급 도구',
    panel('실험 기능',row('녹음 중 미리보기',toggle('preview','녹음 중 미리보기'),helpText.preview,memory.preview?(memory.speaker?'현재 미적용 · 내 목소리 필터 켜짐':!local()?'현재 미적용 · 로컬 인식에서 사용':'추가 연산 · 확정 결과 아님'):'')+
      row('내 목소리 구분',go('모델·등록 관리','speaker-setup','quiet'),helpText.speaker,'실험 · 기본 꺼짐')+
      row('번역 문장 다듬기',toggle('refine','번역 문장 다듬기'),helpText.refine,memory.refine?'추가 요청 1회 · 실패 시 입력 보류':'')+
      row('Jev 추가 도움',go('세부 옵션','jev-assistance','quiet'),helpText.review)+
      row('음성 모델 비교',go('같은 음성 비교','speech-lab','quiet'),'내려받은 로컬 모델만 같은 음성으로 순차 비교합니다. API 요청·새 다운로드·기록 보관 없이 비교합니다.')+
      row('문장 모델 비교',go('승인한 문장 비교','text-lab','quiet'),'직접 승인한 사례와 2~3개 모델을 예산 안에서 비교합니다. 전송·비용 확인과 직접 모델 적용을 유지합니다.','추가 API 요청·비용'))+
    panel('문제 해결',row('Mac 접근 권한',go('권한 상태','permissions','quiet'),'마이크와 손쉬운 사용 권한은 System Settings에서 관리합니다.')+
      row('다른 앱 입력',go('입력 테스트','input-diagnostics','quiet'),'테스트 문구를 실제 입력하는 기존 진단이며 녹음·API·메시지 전송은 하지 않습니다.')+
      row('연결·처리 시간',go('진단 상세','input-diagnostics','quiet'),'최근 실제 처리 단계 시간을 표시합니다. 입력 확인 대기는 글이 나타난 시각과 다를 수 있습니다.')+
      row('Jev 연결 확인',go('연결 테스트','jev-settings','quiet'),'고정 합성 문장으로 실제 연결을 확인합니다. API 비용과 사용량 기록이 생길 수 있습니다.')),true));
  add('models','음성 모델',()=>shell('models','음성 모델',
    panel('사용할 모델',row('현재 처리',badge(local()?'이 Mac에서 인식':'온라인 인식',local()?'success':''),helpText.processing)+
      row('인식 모델',select('model',[['large','Whisper Large v3'],['small','Whisper Small'],['base','Whisper Base']]),'모두 한국어·영어를 지원하지만 혼용·고유명사 정확도를 보장하지 않습니다. 작은 모델은 자원 사용을 줄일 수 있습니다. 다운로드만으로 인식 방식은 바뀌지 않습니다.')+
      row('선택 모델 관리',go('파일·메모리','model-detail','quiet'),'선택, 파일 저장, 메모리 준비를 구분합니다.'))+
    panel('모델 파일',[['large','Whisper Large v3','파일 저장됨'],['small','Whisper Small','준비 필요'],['base','Whisper Base','준비 필요']].map(([key,name,status])=>row(name,badge(status)+go('관리','model-detail','quiet').replace('data-go=',`data-b-model="${key}" data-go=`),'각 모델 파일과 토크나이저를 따로 확인하고 선택 모델만 삭제합니다.')).join(''))+
    panel('관련 도구',row('내 음성으로 비교',go('음성 모델 비교','speech-lab','quiet'),'같은 음성으로 비교하며 CER·숫자·고유명사는 별도로 확인합니다.')+
      row('내 목소리 구분',go('화자 모델·등록','speaker-setup','quiet'),helpText.speaker)),false,go('AI 연결','settings-connections','quiet')),'모델');
  const modelDetail = state => shell(state==='ready'?'model-detail':state==='preparing'?'model-preparing':'model-error',modelTitle(),
    (state==='error'?'<div class="callout"><span class="badge danger">모델 준비 실패</span><span>연결을 확인한 뒤 다시 준비해 주세요.</span></div>':'')+
    panel('파일과 준비',row('파일',badge(memory.model==='large'?'저장됨':'준비 필요',memory.model==='large'?'success':''),'파일 저장과 메모리 준비는 별개이며 모델·토크나이저가 모두 필요합니다.')+
      row('메모리',badge(state==='ready'&&memory.model==='large'?'준비됨':state==='preparing'?'준비 중':'미준비',state==='ready'&&memory.model==='large'?'success':state==='error'?'danger':'warn'),'메모리 준비를 마친 뒤 로컬 인식에 사용할 수 있습니다.')+
      row('모델 준비',state==='preparing'?toast('준비 취소','모델 준비 취소 화면 시안입니다. 실제 다운로드를 하지 않습니다.','quiet'):state==='ready'&&memory.model==='large'?badge('준비됨','success'):go(state==='error'?'다시 준비':'다운로드·준비','model-preparing','primary'),'준비와 취소는 기존 작업 단위 보호를 유지합니다. 이미 준비된 모델은 준비 버튼으로 다시 시작하지 않습니다.')+
      row('선택 모델 파일',go('파일 삭제…','model-delete-confirm','danger').replace('<button ',state==='preparing'?'<button disabled ':'<button '),'이 모델만 삭제하며 기록·사전·다른 모델은 보존합니다.'))+
    panel('자원 사용',row('메모리 유지',select('unload',[['never','계속 유지'],['5','5분 미사용 후 해제'],['15','15분 미사용 후 해제'],['30','30분 미사용 후 해제']]),'해제해도 파일은 남고 다음 녹음에 다시 메모리를 준비하므로 첫 반응이 느려질 수 있습니다.')+
      row('녹음 중 미리보기',toggle('preview','녹음 중 미리보기'),helpText.preview,memory.preview?(memory.speaker?'현재 미적용 · 화자 필터 사용':'실험 · 추가 연산'):'실험 기능'))+
    `<nav class="tabs" aria-label="모델 상태 시안">${go('준비됨','model-detail','quiet')}${go('준비 중','model-preparing','quiet')}${go('실패','model-error','quiet')}</nav>`,false,go('모델 목록','models','quiet'));
  add('model-detail','모델 상세',()=>modelDetail('ready'),'모델');
  add('model-preparing','모델 준비 중',()=>modelDetail('preparing'),'상태');
  add('model-error','모델 준비 실패',()=>modelDetail('error'),'상태');
  add('model-delete-confirm','모델 파일 삭제 확인',()=>shell('model-delete-confirm','선택 모델 파일 삭제',
    panel('삭제 범위',row('삭제할 모델',badge(modelTitle()),'모델·토크나이저의 해당 파일만 삭제합니다.')+
      row('유지할 데이터','기록 · 개인 사전 · 다른 모델','이 삭제는 텍스트 기록·개인 사전·다른 모델 파일을 삭제하지 않습니다.')+
      row('다시 사용하려면',badge('재다운로드 필요','warn'),'선택 모델을 다시 내려받아 준비해야 합니다.'))+
    `<div class="toolbar">${go('취소','model-detail','quiet')}${toast('모델 파일 삭제','삭제 확인 화면 시안입니다. 실제 파일은 삭제하지 않습니다.','danger')}</div>`),'확인');
  const modelChoices = [['default','제공자 기본 모델'],['openai/gpt-6-luna','GPT-6 Luna'],['openai/gpt-oss-120b','GPT OSS 120B'],['openai/gpt-4.1-mini','GPT-4.1 Mini'],['custom','직접 입력…']];
  const effectiveTextProvider = () => memory.textProvider==='shared'?memory.speechProvider:memory.textProvider;
  const keyServiceTitle = () => ({speech:'음성 인식',text:'문장 처리',jev:'Jev 검토'})[memory.connectionTarget];
  const connectionServiceRows = () => memory.connectionTarget==='jev'
    ? row('검토 연결',select('reviewProvider',[['openRouter','OpenRouter 키 재사용'],['typeSafe','Jev API 직접 연결']]),'직접 연결은 TypeSafe 키를 사용합니다. 재사용은 OpenRouter 문장 연결에서 관리하는 키를 사용합니다.')
    : memory.connectionTarget==='speech'
      ? row('음성 제공자',select('speechProvider',providers),'서비스마다 저장한 키와 모델을 유지합니다.')+
        row('음성 모델',select('speechModel',memory.speechProvider==='groq'?[['default','제공자 기본 모델'],['whisper-large-v3-turbo','Whisper Large v3 Turbo'],['whisper-large-v3','Whisper Large v3'],['custom','직접 입력…']]:[['default','제공자 기본 모델'],['custom','직접 입력…']]),'Groq는 기존 음성 모델 목록과 직접 입력을 제공합니다. 다른 제공자에서는 모델 ID를 직접 지정할 수 있습니다.')+
        (memory.speechModel==='custom'?row('모델 ID','<input class="input" aria-label="음성 모델 ID 직접 입력" placeholder="모델 ID">','빈 값은 해당 제공자의 기존 기본 모델을 사용합니다.'):'')
      : row('문장 제공자',select('textProvider',[['shared','음성 제공자 재사용'],...providers]),'같은 제공자의 키를 공유하는 기존 조건을 유지합니다.')+
        row('문장 모델',select('textModel',effectiveTextProvider()==='openRouter'?modelChoices:effectiveTextProvider()==='groq'?[['default','제공자 기본 모델'],['openai/gpt-oss-120b','GPT OSS 120B'],['custom','직접 입력…']]:[['default','제공자 기본 모델'],['custom','직접 입력…']]),'OpenRouter·Groq의 기존 목록과 직접 입력 경로를 유지합니다. 이 시안은 계정별 모델 사용 가능 여부를 확인하지 않습니다.')+
        (memory.textModel==='custom'?row('모델 ID','<input class="input" aria-label="문장 모델 ID 직접 입력" placeholder="모델 ID">','직접 입력 모델의 가격은 제공자에서 확인해야 합니다.'):'')+
        row('가격 기준·모델 정보',toast('정보 보기','모델 가격 기준과 출처 화면 시안입니다. 실제 가격 API를 호출하지 않습니다.','quiet'),'기존 목록의 100만 토큰당 참고 단가·기준일·출처·모델별 주의를 상세에서 유지합니다. 정확한 가격은 시안에 만들지 않습니다.');
  add('api-connection','API 연결 상세',()=>shell('api-connection',keyServiceTitle()+' 연결',
    panel('서비스',connectionServiceRows())+
    (memory.connectionTarget==='jev'&&memory.reviewProvider==='openRouter'
      ? panel('공유하는 키',row('OpenRouter 문장 키',connection('문장 키 관리','text'),helpText.key,effectiveTextProvider()==='openRouter'?'문장 연결의 키 재사용':'현재 문장 제공자 OpenRouter 필요'))
      : panel('키 관리',row('저장 상태',badge('예시 · 저장됨')+badge('연결 미확인','warn'),helpText.key)+
      row('API 키','<input class="input" type="password" aria-label="API 키 시안 입력" placeholder="실제 키를 입력하지 마세요" autocomplete="off">',helpText.key)+
      row('키 적용',toast('Keychain에 저장','키 저장 화면 시안입니다. 실제 Keychain에 접근하지 않습니다.','primary')+go('삭제…','key-delete-confirm','danger'),helpText.key)+
      row('저장된 키 다시 확인',toast('다시 확인','키 상태 확인 시안입니다. 실제 Keychain을 조회하지 않습니다.','quiet'),helpText.key))),false,go('AI 연결','settings-connections','quiet')));
  add('key-delete-confirm','API 키 삭제 확인',()=>shell('key-delete-confirm','저장된 API 키 삭제',
    panel('변경 범위',row('서비스',badge(keyServiceTitle()),'선택한 서비스의 키만 삭제합니다. 다른 제공자의 키는 유지됩니다.')+
      row('다음 작업',badge('키 재설정 필요','warn'),'해당 서비스가 필요한 작업은 키를 준비할 때까지 시작할 수 없거나 기존 실패 정책을 따릅니다.'))+
    `<div class="toolbar">${go('취소','api-connection','quiet')}${toast('저장된 키 삭제','키 삭제 확인 시안입니다. 실제 키는 삭제하지 않습니다.','danger')}</div>`),'확인');
  add('jev-settings','문장 검토 · Jev',()=>shell('jev-settings','문장 검토 · Jev',
    panel('연결',row('검토 서비스',select('reviewProvider',[['openRouter','OpenRouter 키 재사용'],['typeSafe','Jev API 직접 연결']]),'OpenRouter 재사용은 문장 제공자가 OpenRouter일 때 가능합니다. 직접 연결은 문장 제공자와 독립입니다.')+
      row('검토 API 키',connection('키 관리','jev'),helpText.key,'예시 · 연결 미확인'))+
    panel('입력과 검토',row('자동 검토',select('review',modes),helpText.review,reviewStatus())+
      row('번역도 입력 전 검토',toggle('translationReview','번역 입력 전 검토',memory.review!=='protect'),helpText.translationReview,memory.review!=='protect'?'현재 미적용 · 입력 전 확인에서 사용':memory.translationReview?'추가 요청 · 번역 검토 실패 시 보류':'')+
      row('오류 유형 학습',go(memory.errorLearning?'켜짐':'꺼짐','jev-learning','quiet'),'개인 사전과 별개로 해결한 오류 유형만 모델별 암호화 저장합니다.'))+
    panel('도움과 확인',row('보조 모델',select('improvementModel',[['default','현재 문장 모델 재사용'],...modelChoices.filter(x=>x[0]!=='default')]),'직접 요청한 개선안과 입력 전 보호의 별도 개선안에 사용합니다. repair·observe 교정은 현재 문장 모델을 사용합니다.')+
      (memory.improvementModel==='custom'?row('보조 모델 ID','<input class="input" aria-label="보조 모델 ID" placeholder="모델 ID 직접 입력">','현재 문장 제공자의 모델을 사용합니다. 미지정이면 현재 문장 모델을 재사용합니다.'):'')+
      row('보조 모델 기본값',toast('현재 문장 모델과 같게','보조 모델 복원 시안입니다. 실제 모델 설정은 바꾸지 않습니다.','quiet'),'제공자별 별도 보조 모델 값을 지우는 기존 복원 동작을 유지합니다.')+
      row('추가 도움 기능',go('세부 옵션','jev-assistance','quiet'),helpText.review)+
      row('최근 검토 결과',go('결과·표기 제안','review','quiet'),'최근 검토가 있는 경우 해당 결과·표기 제안으로 이동합니다. 이전 결과가 없으면 비활성으로 표시합니다.')+
      row('Jev 연결 테스트',toast('연결 테스트','고정 합성 문장 연결 테스트 시안입니다. 실제 유료 요청은 하지 않습니다.','quiet'),'실제 앱에서는 합성 문장 한 건으로 연결을 확인하며 API 비용·사용량 기록이 발생할 수 있습니다.','실행 시 추가 요청·비용')),
    false,go('받아쓰기','settings-dictation','quiet')));
  add('jev-assistance','Jev 추가 도움',()=>shell('jev-assistance','추가 도움 기능',
    panel('검토 조절',row('중요한 변경 세부 검토',toggle('detailed','중요한 변경 세부 검토'),'숫자·부정·조건·요청·이름의 질문을 기존 Jev 검토에 추가합니다. 별도 요청 수를 늘린다는 뜻은 아니며 비용은 늘 수 있습니다.',memory.detailed?'검토 질문 추가 · 비용 증가 가능':'')+
      row('단순 받아쓰기 검토 절약',toggle('economy','단순 받아쓰기 검토 절약'),'비어 있지 않은 원문·결과가 동일하고 표기 후보가 없을 때만 자동 검토를 생략합니다. 생략은 검토 통과가 아니며 직접 요청한 검토는 유지합니다.',memory.economy?'조건에 따라 자동 검토 생략':'')+
      row('주의 신호 시 개선안 준비',toggle('alternatives','주의 신호 시 개선안 준비'),'입력 전 보호·말한 언어 유지·AI 정리에서만 별도 개선안과 검토를 추가합니다. 결과는 확인 후 복사하며 자동 대체하지 않습니다.',memory.alternatives?(fast()||translation()||memory.review!=='protect'?'현재 미적용 · AI 정리·입력 전 확인에서 사용':'추가 생성·검토 요청 · 확인 후 복사'):'')+
      row('해결한 오류 유형 반영',go(memory.errorLearning?'켜짐':'꺼짐','jev-learning','quiet'),'모델별 정해진 오류 유형만 다음 기존 문장 요청에 포함하며 모델 재학습이 아닙니다.'))+
    panel('작업 도움',row('모호한 수정 지시 확인',toggle('clarify','모호한 수정 지시 확인'),'선택 원문·수정 지시를 Jev에 추가 전송합니다. 모호하면 입력을 보류하고 구체적인 지시를 받습니다. 수정안은 확인 후 복사합니다.',memory.clarify?'원문·수정 지시 추가 전송 · 비용 발생 가능':'')+
      row('헷갈리는 음성 재인식',toggle('reRecognition','헷갈리는 음성 재인식'),'지원되는 받아쓰기에서 같은 녹음을 Groq/OpenAI에 한 번 더 보내고 두 인식문을 Jev로 비교합니다. 추가 비용이 발생하고 자동 교체하지 않습니다. observe도 입력 전 대기가 생길 수 있습니다.',memory.reRecognition?'녹음 외부 재전송 · 추가 요청·비용':'')),false,go('검토 설정','jev-settings','quiet')));
  add('jev-learning','Jev 오류 유형 학습',()=>shell('jev-learning','오류 유형 학습',
    panel('다음 요청에 반영',row('해결한 오류 유형 기억',toggle('errorLearning','해결한 오류 유형 기억'),'재검토를 통과한 정해진 오류 유형을 모델별로 암호화 저장합니다. 다음 기존 문장 요청에 주의사항을 포함합니다. 과거 문장은 저장하지 않으며 AI 모델 재학습이 아닙니다.',memory.errorLearning?'다음 문장 요청에 포함 · 별도 요청 없음':'')+
      row('현재 문장 모델',badge('예시 · 현재 모델'),'제공자·모델별로 학습 범위를 구분합니다.')+
      row('저장된 오류 유형',badge('0개'),'현재 모델에 저장한 유형의 개수와 제목을 표시합니다.')+
      row('모든 모델의 유형',go('지우기…','jev-clear-confirm','danger'),'모든 오류 유형만 삭제하며 개인 사전과 텍스트 기록은 유지합니다.')),false,go('추가 도움','jev-assistance','quiet')));
  add('jev-clear-confirm','오류 유형 삭제 확인',()=>shell('jev-clear-confirm','학습한 오류 유형 삭제',
    panel('삭제 범위',row('삭제할 데이터','모든 모델의 Jev 오류 유형','이 Mac의 암호화된 오류 유형만 삭제합니다.')+
      row('유지할 데이터','개인 사전 · 텍스트 기록','사전 표기와 기존 문장 기록은 지우지 않습니다.'))+
    `<div class="toolbar">${go('취소','jev-learning','quiet')}${toast('오류 유형 모두 삭제','삭제 확인 시안입니다. 실제 데이터를 삭제하지 않습니다.','danger')}</div>`),'확인');
  add('permissions','Mac 접근 권한',()=>shell('permissions','Mac 접근 권한',
    panel('권한 상태',row('마이크',badge('예시 · 허용 필요','warn')+toast('사용 요청','마이크 권한 요청 시안입니다. 실제 권한을 요청하지 않습니다.','quiet')+toast('시스템 설정','마이크 설정 진입 시안입니다. 실제 설정을 열지 않습니다.','quiet'),'사용자가 시작한 녹음에 사용하며 거부 상태에서는 System Settings에서 허용합니다.')+
      row('손쉬운 사용',badge('예시 · 허용됨','success')+toast('시스템 설정','손쉬운 사용 설정 진입 시안입니다. 실제 설정을 열지 않습니다.','quiet'),'선택한 문장을 읽고 다른 앱의 입력창에 글을 넣는 데 사용합니다.')+
      row('현재 상태',toast('다시 확인','권한 새로고침 화면 시안입니다. 실제 권한 상태를 조회하지 않습니다.','quiet'),'실제 앱이 활성화되면 권한을 다시 확인합니다.'))+
    panel('입력 확인',row('다른 앱 입력',go('입력 테스트','input-diagnostics','quiet'),'권한 허용은 실제 입력 성공을 보장하지 않으며 대상 앱에서 별도 확인합니다.')),false,go('고급 도구','settings-advanced','quiet')));
  add('input-diagnostics','입력·연결 진단',()=>shell('input-diagnostics','입력·연결 진단',
    panel('녹음 없이 입력 확인',row('단축키로 테스트',toast('테스트 준비','테스트 준비 화면 시안입니다. 다른 앱에 문구를 입력하지 않습니다.','primary'),'실제 앱은 준비 후 대상 입력창의 받아쓰기 단축키를 누르면 테스트 문구를 넣습니다. 녹음·API·메시지 전송은 하지 않습니다.')+
      row('5초 뒤 테스트',toast('5초 뒤 시작','예약 입력 테스트 시안입니다. 실제 타이머나 입력을 시작하지 않습니다.','quiet'),'기존 예약 테스트 경로입니다. 준비 중에는 취소 동작을 유지합니다.')+
      row('준비 상태',badge('준비 전')+toast('준비 취소','입력 테스트 취소 시안입니다.','quiet').replace('<button ','<button disabled '),'준비한 상태에서만 취소가 활성화됩니다.')+
      row('단축키 충돌',toast('충돌 확인','충돌 확인 시안입니다. 실제 시스템 단축키를 조회하지 않습니다.','quiet'),'현재 등록 상태와 다른 앱 충돌 경고를 표시합니다.'))+
    panel('최근 진단',row('입력 확인',badge('아직 진단 없음'),'이벤트 전송·실제 입력 확인·확인 불가를 구별합니다.')+
      row('최근 처리 시간',badge('측정 전'),'실제 녹음·인식·정리·검토·입력 단계의 시간만 표시합니다. 입력 확인 대기는 화면에 글이 나타나는 시각과 다를 수 있습니다.')+
      row('Jev 연결',go('연결 테스트','jev-settings','quiet'),'연결 테스트는 유료 요청이 될 수 있으므로 입력 테스트와 구별합니다.')),false,go('고급 도구','settings-advanced','quiet')));
  add('context-apps','앱별 주변 문맥',()=>shell('context-apps','주변 문맥 허용',
    panel('허용된 앱',`<div class="empty"><h2>허용한 앱 없음</h2>${help('주변 문맥','허용한 앱에서만 커서 앞 최대 1,000자를 AI에 전송합니다. 보안 입력란은 제외하고 문맥은 기록에 보관하지 않습니다. 앱별 문체 설정과 독립입니다.')}${toast('앱 추가…','앱 선택 화면 시안입니다. 설치 앱을 조회하거나 전송하지 않습니다.','primary')}</div>`)+
    panel('허용 범위',row('읽는 내용','커서 앞 최대 1,000자','명시적으로 허용한 앱만 읽습니다. 웹사이트·대화 상대별 허용이 아닙니다.')+
      row('보관','기록에 저장하지 않음','기존 문맥 보관 정책을 유지합니다.')),false,go('개인정보','settings-privacy','quiet')));
  add('context-apps-allowed','주변 문맥 허용된 앱',()=>shell('context-apps-allowed','주변 문맥 허용',
    panel('허용된 앱',row('메모',toast('허용 해제','주변 문맥 허용 해제 시안입니다. 실제 설정은 바꾸지 않습니다.','quiet'),'명시적으로 허용한 앱의 커서 앞 최대 1,000자만 현재 AI 처리에 전달합니다.','예시 · 허용됨')+
      row('앱 추가',toast('앱 추가…','앱 선택 시안입니다. 설치 앱을 조회하지 않습니다.','quiet'),'앱별 허용은 사이트·대화 상대별 구분이 아닙니다.')),
    false,go('개인정보','settings-privacy','quiet')),'상태');
  add('writing-profiles','앱별 작성 방식',()=>shell('writing-profiles','앱별 작성 방식',
    `<div class="callout">${fast()?'현재 미적용 · 빠른 로컬 받아쓰기':translation()?'앱별 말투를 번역에 적용':'말한 말투 유지 · 지정한 앱만 변경'}${help('앱별 작성 방식',helpText.profiles)}</div>`+
    panel('앱 설정',[['Codex','개발'],['Mail','이메일'],['메모','메모']].map(([app,kind])=>row(app,`<select class="select" aria-label="${app} 작성 형식" style="width:80px">${[['일반','general'],['대화','conversation'],['메모','notes'],['개발','development'],['이메일','email']].map(([title])=>`<option ${title===kind?'selected':''}>${title}</option>`).join('')}</select><select class="select" aria-label="${app} 말투" style="width:112px"><option>말한 말투 유지</option><option>자연스러운 존댓말</option><option>편한 반말</option><option>격식 있는 존댓말</option></select>${toast('↺',app+' 기본값 복원 시안입니다. 실제 설정을 바꾸지 않습니다.','quiet')}`,helpText.profiles,'예시 · 기본 설정')).join(''),toast('앱 추가…','앱 추가 화면 시안입니다. 실제 앱 목록을 읽지 않습니다.','quiet')),
    false,go('받아쓰기','settings-dictation','quiet')));
  add('speaker-setup','내 목소리 구분',()=>shell('speaker-setup','내 목소리 구분',
    panel('화자 모델',row('실험 상태',badge('실사용 성능 미검증','warn'),helpText.speaker)+
      row('모델 준비',badge('예시 · 준비됨','success'),'화자 모델은 약 14 MB이며 음성 인식 모델과 별도로 준비합니다.')+
      row('내 목소리 등록',badge('예시 · 미등록')+go('등록 시작','speaker-enrolling','primary'),'조용한 곳에서 10~20초 자연스럽게 말합니다. 등록 원음은 삭제하고 특징만 암호화 저장합니다.')+
      row('다시 등록·삭제',toast('다시 등록','목소리 재등록 화면 시안입니다. 실제 녹음을 시작하지 않습니다.','quiet').replace('<button ','<button disabled ')+toast('삭제…','목소리 특징 삭제 확인 시안입니다. 실제 데이터를 지우지 않습니다.','danger').replace('<button ','<button disabled '),'등록된 프로필이 있을 때만 사용하며 기존 작업 중 변경 방지를 유지합니다.'))+
    panel('녹음에 적용',row('내 목소리 필터',toggle('speaker','내 목소리 필터',true),helpText.speaker,'등록 필요 · 현재 켤 수 없음')+
      row('녹음 중 미리보기',badge(memory.speaker?'현재 미적용':'기존 설정 유지'),'화자 필터가 켜지면 미리보기를 일시 미적용하고 저장된 미리보기 설정은 유지합니다.')),false,go('모델 목록','models','quiet')),'모델');
  add('speaker-enrolling','목소리 등록 중',()=>shell('speaker-enrolling','목소리 등록 중',
    panel('등록 녹음',row('현재 단계',badge('예시 · 목소리 등록','warn'),'실제 녹음이 아닌 상태 시안입니다.')+
      row('녹음 시간','00:12','조용한 곳에서 혼자 10~20초 자연스럽게 말합니다.')+
      row('등록 녹음 종료',toast('녹음 종료','등록 녹음 종료 시안입니다. 실제 마이크를 사용하지 않습니다.','primary'),'등록 음성을 처리한 뒤 원음은 삭제합니다.')+
      row('작업 취소',go('취소','speaker-setup','quiet'),'등록 작업의 취소와 원음 정리 정책을 유지합니다.')),false,go('목소리 설정','speaker-setup','quiet')),'상태');
  add('hotkey-capture','단축키 입력 중',()=>shell('hotkey-capture','새 단축키 입력',
    panel('받아쓰기 단축키',row('현재 단계',badge('새 조합을 누르세요','warn'),'시스템 이벤트를 읽지 않는 시안입니다. 실제 앱은 분류 변경·이동·설정 복구가 필요해지면 단축키 캡처를 해제합니다.')+
      row('충돌',badge('다른 작업과 중복','danger'),'중복 조합을 저장하지 않고 기존 등록값을 유지합니다.')+
      row('현재 단축키','⌥ Space','실제 새 조합 검증을 통과해야 변경됩니다.'))+
    `<div class="toolbar">${go('취소','settings-recording','quiet')}${help('단축키 입력 종료','분류 변경·화면 닫기·설정 복구 필요 상태에서 이벤트 모니터를 해제합니다. 잘못된 조합과 중복은 기존 단축키를 바꾸지 않습니다.')}</div>`),'상태');
  add('login-item-error','로그인 항목 등록 오류',()=>shell('login-item-error','로그인 항목 확인',
    `<div class="callout"><span class="badge warn">로그인 항목 확인 필요</span><span>실제 등록 상태를 확인해 주세요.</span></div>`+
    panel('다음 행동',row('등록 상태',badge('예시 · 등록 미확인','warn'),'실제 로그인 항목 서비스의 상태·오류를 표시하며 설정값만 켜졌다고 등록 완료로 표시하지 않습니다.')+
      row('Mac 로그인 항목',toast('시스템 설정','로그인 항목 진입 시안입니다. 실제 설정을 열지 않습니다.','primary'),'기존 시스템 설정 진입 경로를 유지합니다.')),false,go('앱 관리','settings-general','quiet')),'상태');
  add('api-save-error','API 키 저장 오류',()=>shell('api-save-error','API 키 저장 확인',
    `<div class="callout"><span class="badge danger">키를 저장하지 못했습니다</span><span>Keychain 접근 상태를 확인해 주세요.</span></div>`+
    panel('저장 상태',row('서비스',badge(keyServiceTitle()),helpText.key)+
      row('기존 키',badge('저장 여부 다시 확인 필요','warn'),'저장 오류를 연결 성공으로 표시하지 않으며 실제 키 저장·삭제 결과에 맞는 문구를 표시합니다.')+
      row('키 다시 확인',toast('다시 확인','키 상태 확인 시안입니다. 실제 Keychain을 조회하지 않습니다.','quiet'),helpText.key)),false,go('연결 관리','api-connection','quiet')),'상태');
  add('speaker-enrolled','내 목소리 등록됨',()=>shell('speaker-enrolled','내 목소리 구분',
    panel('화자 모델과 등록',row('모델 준비',badge('예시 · 준비됨','success'),helpText.speaker)+
      row('목소리 특징',badge('예시 · 등록됨','success'),'원음은 삭제하고 특징만 암호화 저장한 상태의 배치 시안입니다.')+
      row('등록 관리',go('다시 등록','speaker-enrolling','quiet')+toast('삭제','목소리 특징 삭제 시안입니다. 실제 데이터는 지우지 않습니다.','danger'),'실제 앱의 작업 중 변경 방지와 기존 삭제 동작을 유지합니다.'))+
    panel('녹음에 적용',row('내 목소리 필터',toggle('speaker','내 목소리 필터'),helpText.speaker,memory.speaker?'실험 · 미리보기 일시 미적용':'실험 기능')),
    false,go('모델 목록','models','quiet')),'상태');
  add('speaker-preparing','화자 모델 준비 중',()=>shell('speaker-preparing','화자 모델 준비',
    panel('모델 준비',row('현재 단계',badge('예시 · 준비 중','warn'),helpText.speaker)+
      row('준비 취소',toast('취소','화자 모델 준비 취소 시안입니다. 실제 다운로드는 없습니다.','quiet'),'실제 준비 작업이 있을 때만 취소를 표시합니다.')+
      row('목소리 등록','<button class="button" disabled>등록 시작</button>','모델 준비 완료 전에는 등록을 시작하지 않습니다.')),false,go('목소리 설정','speaker-setup','quiet')),'상태');
  add('speaker-error','화자 모델 준비 오류',()=>shell('speaker-error','화자 모델 준비 확인',
    `<div class="callout"><span class="badge danger">모델 준비 실패</span><span>연결을 확인한 뒤 다시 준비해 주세요.</span></div>`+
    panel('다음 행동',row('화자 모델',go('다시 준비','speaker-preparing','primary'),'실제 오류 문구를 표시하며 준비 실패 상태에서 필터를 사용할 수 없습니다.')+
      row('내 목소리 필터',toggle('speaker','내 목소리 필터',true),helpText.speaker,'모델 준비 필요 · 현재 미적용')),false,go('목소리 설정','speaker-setup','quiet')),'상태');
  const languageExample = key => ({original:'오늘 안에 12개 항목을 확인해 주실 수 있을까요? 승인 전에는 공유하지 말아 주세요.','en-US':'Could you review all 12 items by the end of today? Please do not share them before approval.','en-GB':'Could you review all 12 items by the end of today? Please do not share them before approval.',ko:'오늘 안에 12개 항목을 확인해 주실 수 있을까요? 승인 전에는 공유하지 말아 주세요.',ja:'今日中に12項目すべてをご確認いただけますか。承認前には共有しないでください。','zh-Hans':'可以请您在今天之内确认全部12项吗？批准之前请不要分享。','zh-Hant':'可以請您在今天之內確認全部12項嗎？核准之前請不要分享。'})[key];
  add('language-examples','출력 언어 예시',()=>shell('language-examples','출력 언어 예시',
    panel('미리 볼 언어',row('출력 언어',select('exampleLanguage',langs),helpText.language)+
      row('현재 설정',badge(langs.find(x=>x[0]===memory.language)[1]),'미리보기 선택과 현재 설정은 별개입니다. 직접 적용하기 전에는 값을 바꾸지 않습니다.'))+
    `<div class="grid-2">${panel('말한 내용',`<div class="text-body">${languageExample('original')}</div>`)}${panel('입력 결과 예시',`<div class="text-body">${languageExample(memory.exampleLanguage)}</div>`,help('예시 결과','방향을 보여 주는 고정 합성 예시이며 모델 호출·녹음·전송이 없습니다. 실제 결과는 발화와 모델에 따라 다릅니다. 숫자·조건·부정·말투 보존을 확인합니다.'))}</div>`+
    `<div class="toolbar">${go('취소','settings-dictation','quiet')}<button class="button primary" data-b-action="apply-language" data-go="settings-dictation">${langs.find(x=>x[0]===memory.exampleLanguage)[1]} 적용</button></div>`),'예시');
  const expressionExample = key => ({faithful:'자료를 확인하고, 문제가 있으면 알려 주실 수 있을까요?',concise:'자료를 확인해 문제가 있으면 알려 주실 수 있을까요?',summary:'자료 확인 후 문제가 있으면 알려 주실 수 있을까요?',clear:'자료를 확인해 주시고, 문제가 있으면 알려 주실 수 있을까요?',expanded:'자료를 확인해 주실 수 있을까요? 확인하다 문제가 발견되면 알려 주세요.',creative:'자료를 살펴봐 주실 수 있을까요? 문제가 보이면 알려 주세요.'})[key];
  add('expression-examples','표현 방식 예시',()=>shell('expression-examples','표현 방식 예시',
    panel('미리 볼 방식',row('표현 방식',select('exampleExpression',expressions),helpText.expression)+
      row('적용할 편집 강도',badge(memory.exampleExpression==='faithful'?'0':String(memory.strength||40)),helpText.strength,inactiveExpression()?'현재 미적용 · 설정을 적용하지 않음':''))+
    `<div class="grid-2">${panel('말한 내용',`<div class="text-body">자료를 확인하고, 문제가 있으면 알려 주실 수 있을까요?</div>`)}${panel('정리 결과 예시',`<div class="text-body">${expressionExample(memory.exampleExpression)}</div>`,help('표현 예시','고정 합성 예시입니다. 실제 모델 결과가 아니며 새 사실·조건을 넣을 권한이 아닙니다. 예시를 둘러봐도 설정은 바뀌지 않습니다.'))}</div>`+
    `<div class="toolbar">${go('닫기','settings-dictation','quiet')}<button class="button primary" data-b-action="apply-expression" data-go="settings-dictation" ${inactiveExpression()?'disabled':''}>${expressions.find(x=>x[0]===memory.exampleExpression)[1]} 적용</button></div>`),'예시');
  add('licenses','모델·라이선스',()=>shell('licenses','모델·라이선스',
    panel('모델과 코드',row('WhisperKit · Whisper','MIT','모델과 코드의 기존 출처·라이선스 고지를 유지합니다.')+
      row('FluidAudio 코드','Apache-2.0','화자 처리 코드 라이선스입니다.')+
      row('화자 모델','CC BY 4.0','FluidInference, pyannote, WeSpeaker의 기존 출처를 유지합니다.')+
      row('음성 모델 출처',toast('출처 보기','모델 출처 링크 시안입니다. 외부 페이지는 열지 않습니다.','quiet'),'argmaxinc/whisperkit-coreml')+
      row('화자 모델 출처',toast('출처 보기','화자 모델 출처 링크 시안입니다. 외부 페이지는 열지 않습니다.','quiet'),'FluidInference/speaker-diarization-coreml')),false,go('앱 관리','settings-general','quiet')));
  document.addEventListener('change', event => {
    const target = event.target;
    const key = target?.dataset?.bSetting;
    if (!key || !(key in memory)) return;
    memory[key] = target.type === 'checkbox' ? target.checked : target.type === 'range' ? Number(target.value) : target.value;
    if (key === 'expression') {
      if (memory.expression === 'faithful') memory.strength = 0;
      else if (memory.strength === 0) memory.strength = 40;
    }
    refresh(target,key);
  });
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-b-action],[data-b-model],[data-b-target]');
    if (!button || button.disabled) return;
    if (button.dataset.bModel) memory.model = button.dataset.bModel;
    if (button.dataset.bTarget) memory.connectionTarget = button.dataset.bTarget;
    if (button.dataset.bAction === 'apply-language') memory.language = memory.exampleLanguage;
    if (button.dataset.bAction === 'apply-expression' && !inactiveExpression()) {
      memory.expression = memory.exampleExpression;
      memory.strength = memory.expression === 'faithful' ? 0 : memory.strength || 40;
    }
    for (const [id,entry] of entries) entry.html = renderers.get(id)();
  },true);
})();
