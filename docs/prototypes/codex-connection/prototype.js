'use strict';

const concepts = [
  { id: 'a', title: 'Abas sempre à mão', subtitle: 'Os dois serviços, lado a lado.', note: 'Mais próximo do app atual. Você vê as duas opções e alterna sem abrir outro menu.', recommended: true },
  { id: 'b', title: 'Uma conta de cada vez', subtitle: 'Mais espaço para o que importa.', note: 'Um seletor compacto reúne as contas. O popover fica focado no serviço escolhido.' },
  { id: 'c', title: 'Símbolos como atalhos', subtitle: 'Uma troca rápida e visual.', note: 'Os símbolos ficam no topo. Clique no ChatGPT para conectar ou acessar o Codex.' },
];
const states = Object.fromEntries(concepts.map(c => [c.id, freshState()]));
const demoData = {
  claude: { name: 'Claude Code', account: 'Claude · Max', used: 25, free: [75, 44], reset: ['reinicia em 2h40', 'reinicia amanhã 19:00'], total: '43,7M', written: '223 mil', bars: [43, 76, 100, 3, 3], currentBar: 2, start: '08:20', end: '13:20' },
  codex: { name: 'Codex', account: 'Codex · ChatGPT Plus', used: 18, free: [82, 63], reset: ['reinicia em 3h15', 'reinicia sexta 10:00'], total: '12,4M', written: '86 mil', bars: [65, 100, 3, 3, 3], currentBar: 1, start: '08:55', end: '13:55' },
};
let activeConnection = null;
let settingsConcept = null;
let toastTimer;
const connectionDialog = document.querySelector('#connection-dialog');
const settingsDialog = document.querySelector('#settings-dialog');

function freshState() { return { provider: 'claude', codex: 'disconnected', dropdown: false, range: '5h', refreshed: false }; }
function icon(name, classes = '') { return `<svg class="icon ${classes}" aria-hidden="true"><use href="#icon-${name}"/></svg>`; }
function brand(provider, extra = '') { return `<svg class="brand-icon ${provider} ${extra}" aria-hidden="true"><use href="#icon-${provider === 'codex' ? 'openai' : 'claude'}"/></svg>`; }
function action(id, name) { return `data-concept="${id}" data-action="${name}"`; }

function renderConcept(id) {
  const c = concepts.find(c => c.id === id);
  const s = states[id];
  const connected = s.codex === 'connected';
  const d = demoData[s.provider];
  const hasData = s.provider === 'claude' || connected;
  const element = document.querySelector(`#concept-${id}`);
  const template = `
    <div class="concept-title"><div class="concept-kicker"><span>PROPOSTA ${id.toUpperCase()}</span>${c.recommended ? '<span class="recommendation">RECOMENDADA</span>' : ''}</div><h2>${c.title}</h2><p>${c.subtitle}</p></div>
    <div class="desktop"><div class="mac-menubar"><div class="mac-left"><span aria-hidden="true">●</span><span class="mac-app-title">UsageBar</span></div><div class="mac-status"><span class="menubar-usage" aria-label="Barra de menu: ${hasData ? d.name + ', ' + d.used + '% usado' : 'Codex sem conexão'}">${brand(s.provider)}<span class="status-dot"></span>${hasData ? d.used + '%' : '—%'}</span><span>10:40</span></div></div>
      <div class="popover" aria-label="Popover da proposta ${id.toUpperCase()}">
        ${providerControl(id)}
        ${hasData ? usageContent(id) : emptyContent(id)}
        ${hasData && !connected && s.provider === 'claude' ? `<button class="connect-strip" ${action(id, 'connect')}>${brand('codex')}<span>Conectar Codex</span>${icon('arrow')}</button>` : ''}
        <div class="popover-footer"><button ${action(id, 'settings')}>${icon('settings')}Configurações</button><button ${action(id, 'quit')}>Sair</button></div>
      </div>
    </div><div class="concept-note"><span class="note-index">${id.toUpperCase()}</span><p>${c.note}</p></div>`;
  if (element) element.innerHTML = template;
  else document.querySelector('#concepts').insertAdjacentHTML('beforeend', `<article class="concept" id="concept-${id}" aria-label="Proposta ${id.toUpperCase()}: ${c.title}">${template}</article>`);
}

function providerControl(id) {
  const s = states[id];
  const d = demoData[s.provider];
  const connected = s.codex === 'connected';
  if (id === 'a') return `<div class="popover-heading"><h3>UsageBar</h3><span class="connection-state"><span class="live-dot"></span>${connected ? '2 contas' : '1 conta'}</span></div>
    <div class="provider-tabs" role="group" aria-label="Serviço"><button class="provider-tab" ${action(id, 'claude')} aria-pressed="${s.provider === 'claude'}">${brand('claude')}Claude</button><button class="provider-tab" ${action(id, 'codex')} aria-pressed="${s.provider === 'codex'}">${brand('codex')}Codex${!connected ? '<span class="tiny-plus">+</span>' : ''}</button></div>`;
  if (id === 'b') return `<div class="popover-heading"><h3>UsageBar</h3><span class="connection-state">Seus limites</span></div><div class="provider-dropdown"><button class="provider-switch" ${action(id, 'dropdown')} aria-expanded="${s.dropdown}" aria-controls="account-menu-b">${brand(s.provider)}<span class="provider-switch-text"><strong>${d.name}</strong><small>${s.provider === 'codex' && !connected ? 'Conecte sua conta' : d.account}</small></span>${icon('chevron')}</button>${s.dropdown ? `<div class="dropdown-menu" id="account-menu-b"><button ${action(id, 'claude')}>${brand('claude')}Claude Code${s.provider === 'claude' ? icon('check') : '<small>Conectado</small>'}</button><button ${action(id, connected ? 'codex' : 'connect')}>${brand('codex')}${connected ? 'Codex' : 'Conectar Codex'}${s.provider === 'codex' && connected ? icon('check') : connected ? '<small>Conectado</small>' : '<small>+</small>'}</button></div>` : ''}</div>`;
  return `<div class="popover-heading"><h3>UsageBar</h3><span class="connection-state"><span class="live-dot"></span>${connected ? '2 contas' : '1 conta'}</span></div><div class="icon-rail" role="group" aria-label="Serviço"><button class="rail-provider" ${action(id, 'claude')} aria-label="Ver Claude" title="Claude Code" aria-pressed="${s.provider === 'claude'}">${brand('claude')}</button><button class="rail-provider" ${action(id, 'codex')} aria-label="${connected ? 'Ver Codex' : 'Conectar Codex'}" title="${connected ? 'Codex' : 'Conectar Codex'}" aria-pressed="${s.provider === 'codex'}">${brand('codex')}${!connected ? '<span class="connection-badge">+</span>' : ''}</button><span class="rail-label">${d.name}${s.provider === 'codex' && !connected ? '<br>Não conectado' : ''}</span></div>`;
}

function usageContent(id) {
  const s = states[id];
  const d = demoData[s.provider];
  const weekly = s.range === 'Semana';
  const heights = weekly ? [35, 70, 54, 100, 2, 2, 2] : d.bars;
  const currentBar = weekly ? 3 : d.currentBar;
  return `<div class="usage-rings">${d.free.map((free, i) => `<div class="ring-block"><div class="ring" style="--free:${free};${free < 50 ? '--ring-color:#c99b42' : ''}" role="img" aria-label="${i === 0 ? '5 horas' : 'Semana'}: ${free}% livre"><svg viewBox="0 0 84 84" aria-hidden="true"><circle cx="42" cy="42" r="36"/><circle class="meter" cx="42" cy="42" r="36"/></svg><div class="ring-value"><strong>${free}%</strong><span>livre</span></div></div><div class="ring-label">${i === 0 ? '5 horas' : 'Semana'}</div><div class="ring-reset">${d.reset[i]}</div></div>`).join('')}</div>
    <div class="tokens-card"><div class="tokens-top"><strong>Tokens</strong><div class="mini-segment" role="group" aria-label="Período dos tokens"><button ${action(id, 'range-5h')} aria-pressed="${!weekly}">5h</button><button ${action(id, 'range-week')} aria-pressed="${weekly}">Semana</button></div></div><div class="token-figures"><span>${weekly ? (s.provider === 'claude' ? '128,6M' : '48,2M') : d.total}<small>total</small></span><span>${weekly ? (s.provider === 'claude' ? '641 mil' : '312 mil') : d.written}<small>escritos</small></span></div><div class="token-chart" aria-label="Gráfico ilustrativo de tokens">${heights.map((h, i) => `<button class="token-bar ${i === currentBar ? 'current' : ''} ${i > currentBar ? 'future' : ''}" style="--height:${h}%" ${action(id, 'bar')} data-bar="${i}" aria-label="${weekly ? ['Segunda','Terça','Quarta','Quinta','Sexta','Sábado','Domingo'][i] : 'Hora ' + (i + 1)}: ${i > currentBar ? 'período futuro' : 'dados ilustrativos'}" title="${i > currentBar ? 'Período futuro' : 'Exemplo: ' + h + ' mil tokens escritos'}"></button>`).join('')}</div><div class="chart-times">${weekly ? ['seg','ter','qua','qui','sex','sáb','dom'].map(day => `<span>${day}</span>`).join('') : `<span>desde ${d.start}</span><span>reset ${d.end}</span>`}</div><p class="local-note">${s.provider === 'claude' ? 'Só o Claude Code deste Mac' : 'Exemplo de visualização de tokens do Codex'}</p></div>
    <div class="updated-row"><span>${s.refreshed ? 'Atualizado agora' : 'Atualizado há 1 min'}</span><button class="icon-button" ${action(id, 'refresh')} aria-label="Atualizar ${d.name}">${icon('refresh')}</button></div>`;
}

function emptyContent(id) {
  const s = states[id];
  const waiting = s.codex === 'connecting';
  const failed = s.codex === 'error';
  return `<div class="connection-empty"><div class="empty-logo">${brand('codex')}</div><h4>${waiting ? 'Falta só o login' : failed ? 'Vamos tentar de novo?' : 'Seu Codex, aqui.'}</h4><p>${waiting ? 'Conclua o login para acompanhar os limites da sua conta.' : failed ? 'Não foi possível concluir a conexão. Você pode tentar novamente.' : 'Conecte sua conta do ChatGPT para acompanhar os limites do Codex.'}</p><button class="primary-button" ${action(id, waiting ? 'resume-login' : 'connect')}>${brand('codex')}${waiting ? 'Continuar conexão' : failed ? 'Tentar novamente' : 'Conectar Codex'}</button><p class="privacy-note">O login é feito pelo próprio Codex.</p></div>`;
}

function startConnection(id) {
  if (settingsDialog.open) settingsDialog.close();
  activeConnection = id;
  states[id].provider = 'codex';
  states[id].dropdown = false;
  renderConcept(id);
  renderConnection('intro');
  if (!connectionDialog.open) connectionDialog.showModal();
}

function renderConnection(phase) {
  const id = activeConnection;
  let content;
  let lab = '';
  if (phase === 'intro') {
    content = `<div class="empty-logo">${brand('codex')}</div><h2 id="connection-title">Conectar Codex</h2><p>Entre com sua conta do ChatGPT.<br>Seus limites ficam a um clique de distância.</p><ol class="login-steps"><li><span>1</span>Inicie a conexão com o Codex.</li><li><span>2</span>Conclua o login na sua conta.</li><li><span>3</span>Volte ao UsageBar para ver seus limites.</li></ol><button class="primary-button" data-login="begin">${brand('codex')}Entrar com ChatGPT${icon('external')}</button><p class="dialog-fineprint">A autenticação é gerenciada pelo Codex.</p>`;
    lab = 'Protótipo visual. O próximo botão simula o início da autenticação; nenhuma conta será acessada.';
  } else if (phase === 'waiting') {
    content = `<div class="empty-logo">${brand('codex')}</div><h2 id="connection-title">Conclua seu login</h2><p>Continue na experiência de login do Codex.<br>Quando terminar, volte para o UsageBar.</p><div class="waiting-row"><span class="waiting-indicator" aria-hidden="true"></span>Aguardando sua conexão…</div><button class="secondary-button" data-login="cancel">Cancelar conexão</button>`;
    lab = `<span>CONTROLES DO PROTÓTIPO</span><div class="simulation-buttons"><button class="simulate-success" data-login="success">Simular login concluído</button><button data-login="error">Simular falha</button></div>`;
  } else if (phase === 'success') {
    content = `<div class="success-symbol">${icon('check')}</div><h2 id="connection-title">Codex conectado.</h2><p>Pronto. Agora você pode alternar entre Claude e Codex sempre que precisar.</p><button class="primary-button" data-login="done">Ver limites do Codex${icon('arrow')}</button>`;
    lab = 'Conexão simulada. Os limites e o plano exibidos são ilustrativos.';
  } else {
    content = `<div class="empty-logo error-symbol">!</div><h2 id="connection-title">A conexão não foi concluída</h2><p>Você pode tentar novamente ou voltar ao Claude enquanto isso.</p><button class="primary-button" data-login="retry">Tentar novamente</button><button class="secondary-button" data-login="back">Voltar ao Claude</button>`;
    lab = 'Falha simulada para você avaliar como o app se recupera.';
  }
  connectionDialog.innerHTML = `<div class="dialog-toolbar"><span>UsageBar · Proposta ${id.toUpperCase()}</span><button class="icon-button" data-login="close" aria-label="Fechar">${icon('close')}</button></div><div class="dialog-body">${content}</div><div class="simulation-footer">${lab}</div>`;
  if (connectionDialog.open) connectionDialog.querySelector('.dialog-body button')?.focus();
}

function renderSettings(id) {
  settingsConcept = id;
  const connected = states[id].codex === 'connected';
  settingsDialog.innerHTML = `<div class="dialog-toolbar"><span>UsageBar · Proposta ${id.toUpperCase()}</span><button class="icon-button" data-settings="close" aria-label="Fechar configurações">${icon('close')}</button></div><div class="settings-body"><h2 id="settings-title">Suas conexões</h2><p>Escolha quais serviços acompanhar no UsageBar.</p><div class="account-row"><div class="account-logo">${brand('claude')}</div><div class="account-info"><strong>Claude Code</strong><small>Conta Max</small></div><span class="account-connected">${icon('check')}Conectado</span></div><div class="account-row"><div class="account-logo">${brand('codex')}</div><div class="account-info"><strong>Codex</strong><small>${connected ? 'ChatGPT Plus' : 'Entre com sua conta do ChatGPT'}</small></div>${connected ? '<button data-settings="disconnect">Desconectar</button>' : '<button data-settings="connect">Conectar</button>'}</div><p class="settings-note">Cada serviço usa seu próprio login. Os limites aparecem separadamente ao alternar entre as contas.</p></div><div class="simulation-footer">Configurações ilustrativas. Conectar e desconectar afeta apenas esta proposta.</div>`;
  if (!settingsDialog.open) settingsDialog.showModal();
}

function toast(message) {
  const el = document.querySelector('#toast');
  clearTimeout(toastTimer);
  el.textContent = message;
  el.classList.add('visible');
  toastTimer = setTimeout(() => el.classList.remove('visible'), 3200);
}

document.addEventListener('click', event => {
  const button = event.target.closest('button');
  if (!button) return;
  const id = button.dataset.concept;
  if (id) {
    const s = states[id];
    switch (button.dataset.action) {
      case 'claude': s.provider = 'claude'; s.dropdown = false; break;
      case 'codex': s.provider = 'codex'; s.dropdown = false; break;
      case 'dropdown': s.dropdown = !s.dropdown; break;
      case 'connect': startConnection(id); return;
      case 'resume-login': activeConnection = id; renderConnection('waiting'); connectionDialog.showModal(); return;
      case 'settings': renderSettings(id); return;
      case 'quit': toast('No app, este botão encerra o UsageBar.'); return;
      case 'range-5h': s.range = '5h'; break;
      case 'range-week': s.range = 'Semana'; break;
      case 'refresh': s.refreshed = true; toast(`${demoData[s.provider].name}: limites de demonstração atualizados.`); break;
      case 'bar': toast(button.title); return;
    }
    const focusAction = button.dataset.action;
    renderConcept(id);
    document.querySelector(`#concept-${id} [data-action="${focusAction}"]`)?.focus({ preventScroll: true });
  }
  if (button.dataset.login) {
    const s = states[activeConnection];
    switch (button.dataset.login) {
      case 'begin': s.codex = 'connecting'; renderConcept(activeConnection); renderConnection('waiting'); break;
      case 'success': s.codex = 'connected'; s.refreshed = true; renderConcept(activeConnection); renderConnection('success'); break;
      case 'error': s.codex = 'error'; renderConcept(activeConnection); renderConnection('error'); break;
      case 'retry': renderConnection('intro'); break;
      case 'back': s.provider = 'claude'; connectionDialog.close(); renderConcept(activeConnection); break;
      case 'cancel': s.codex = 'disconnected'; connectionDialog.close(); renderConcept(activeConnection); break;
      case 'close': connectionDialog.close(); break;
      case 'done': connectionDialog.close(); document.querySelector(`#concept-${activeConnection} [data-action="codex"]`)?.focus({ preventScroll: true }); break;
    }
  }
  if (button.dataset.settings) {
    switch (button.dataset.settings) {
      case 'close': settingsDialog.close(); break;
      case 'connect': startConnection(settingsConcept); break;
      case 'disconnect': states[settingsConcept].codex = 'disconnected'; states[settingsConcept].provider = 'claude'; renderConcept(settingsConcept); renderSettings(settingsConcept); toast('Codex desconectado nesta proposta.'); break;
    }
  }
  if (button.dataset.scenario) setScenario(button.dataset.scenario);
});

document.addEventListener('click', event => {
  if (!event.target.closest('.provider-dropdown') && states.b.dropdown) {
    states.b.dropdown = false;
    renderConcept('b');
  }
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && states.b.dropdown) { states.b.dropdown = false; renderConcept('b'); document.querySelector('[data-action="dropdown"]')?.focus(); }
});

function setScenario(scenario) {
  for (const c of concepts) {
    states[c.id] = freshState();
    if (scenario === 'connected') { states[c.id].codex = 'connected'; states[c.id].provider = 'codex'; }
    renderConcept(c.id);
  }
  document.querySelectorAll('[data-scenario]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.scenario === scenario)));
}

function setTheme(theme) {
  document.documentElement.dataset.theme = theme;
  document.querySelector('#theme-toggle').innerHTML = icon(theme === 'dark' ? 'sun' : 'moon');
  document.querySelector('#theme-toggle').setAttribute('aria-label', `Ativar tema ${theme === 'dark' ? 'claro' : 'escuro'}`);
  try { localStorage.setItem('usagebar-prototype-theme', theme); } catch { /* file:// storage may be restricted */ }
}
document.querySelector('#theme-toggle').addEventListener('click', () => setTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'));
document.querySelector('#reset').addEventListener('click', () => { setScenario('disconnected'); toast('As três propostas voltaram ao início.'); });
for (const dialog of [connectionDialog, settingsDialog]) dialog.addEventListener('click', event => { if (event.target === dialog) { const r = dialog.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) dialog.close(); } });
let initialTheme = 'light';
try { initialTheme = localStorage.getItem('usagebar-prototype-theme') || 'light'; } catch { /* default to light */ }
setTheme(initialTheme === 'dark' ? 'dark' : 'light');
concepts.forEach(c => renderConcept(c.id));
