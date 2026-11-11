/* ==========================================================================
   Glide console — front-end
   Vanilla JS. No build step, no dependencies, no GitHub token.
   The only remote thing this page talks to is the codespace you point it at.
   ========================================================================== */
(() => {
  'use strict';

  const STORAGE_KEY = 'glide.console.v3';
  const PROXY_PORT = 6080;
  const POLL_TIMEOUT = 6000;
  const API_TIMEOUT = 20000;

  const $ = (sel, root = document) => (root || document).querySelector(sel);
  const $$ = (sel, root = document) => Array.from((root || document).querySelectorAll(sel));

  const el = {
    html: document.documentElement,
    views: $('#views'),
    hostChipText: $('#hostChipText'),
    statusPill: $('#statusPill'),
    statusText: $('#statusText'),
    refreshBtn: $('#refreshBtn'),
    openStreamTop: $('#openStreamTop'),
    demoChip: $('#demoChip'),
    themeToggle: $('#themeToggle'),

    connectForm: $('#connectForm'),
    codespaceInput: $('#codespaceInput'),
    connectBtn: $('#connectBtn'),
    probePanel: $('#probePanel'),
    probeTitle: $('#probeTitle'),
    probeSub: $('#probeSub'),
    probeLatency: $('#probeLatency'),
    probeSteps: $('#probeSteps'),
    probeActions: $('#probeActions'),
    probeOpenBtn: $('#probeOpenBtn'),
    probeFixBtn: $('#probeFixBtn'),
    probeTabBtn: $('#probeTabBtn'),

    sessionTag: $('#sessionTag'),
    progressFill: $('#progressFill'),
    statusLine: $('#statusLine'),
    stepList: $('#stepList'),
    kvVersion: $('#kvVersion'),
    kvLoader: $('#kvLoader'),
    kvHeap: $('#kvHeap'),
    kvEncoder: $('#kvEncoder'),
    kvUptime: $('#kvUptime'),
    streamState: $('#streamState'),
    openStreamBtn: $('#openStreamBtn'),

    instRefresh: $('#instRefresh'),
    instEmpty: $('#instEmpty'),
    instBody: $('#instBody'),
    instState: $('#instState'),
    instCurrentVersion: $('#instCurrentVersion'),
    instCurrentLoader: $('#instCurrentLoader'),
    instCurrentHeap: $('#instCurrentHeap'),
    instCurrentMods: $('#instCurrentMods'),
    instModDir: $('#instModDir'),
    instVersion: $('#instVersion'),
    instLoader: $('#instLoader'),
    instHeap: $('#instHeap'),
    instApply: $('#instApply'),
    modCount: $('#modCount'),
    modTarget: $('#modTarget'),
    modDrop: $('#modDrop'),
    modBrowse: $('#modBrowse'),
    modInput: $('#modInput'),
    modUploadState: $('#modUploadState'),
    modList: $('#modList'),
    versionOptions: $('#versionOptions'),

    fileRoot: $('#fileRoot'),
    fileRefresh: $('#fileRefresh'),
    fileEmpty: $('#fileEmpty'),
    fileBody: $('#fileBody'),
    breadcrumb: $('#breadcrumb'),
    fileMkdir: $('#fileMkdir'),
    fileUpload: $('#fileUpload'),
    fileInput: $('#fileInput'),
    fileUploadState: $('#fileUploadState'),
    fileTable: $('#fileTable'),

    logSelect: $('#logSelect'),
    logAuto: $('#logAuto'),
    logRefresh: $('#logRefresh'),
    logCopy: $('#logCopy'),
    logPre: $('#logPre'),
    logStatus: $('#logStatus'),

    settingsEmpty: $('#settingsEmpty'),
    settingsUrl: $('#settingsUrl'),
    settingsKey: $('#settingsKey'),
    settingsAuto: $('#settingsAuto'),
    settingsPoll: $('#settingsPoll'),
    profileGroup: $('#profileGroup'),
    setResolution: $('#setResolution'),
    setBitrate: $('#setBitrate'),
    setFps: $('#setFps'),
    setEncoder: $('#setEncoder'),
    setDashboard: $('#setDashboard'),
    setAudio: $('#setAudio'),
    saveStream: $('#saveStream'),
    setAuthMode: $('#setAuthMode'),
    setUsername: $('#setUsername'),
    setClientId: $('#setClientId'),
    saveMinecraft: $('#saveMinecraft'),
    settingsMotion: $('#settingsMotion'),
    settingsForget: $('#settingsForget'),
    storageNote: $('#storageNote'),

    toastStack: $('#toastStack'),
    confirmDialog: $('#confirmDialog'),
    confirmTitle: $('#confirmTitle'),
    confirmBody: $('#confirmBody'),
    confirmOk: $('#confirmOk'),
    editorDialog: $('#editorDialog'),
    editorTitle: $('#editorTitle'),
    editorPath: $('#editorPath'),
    editorText: $('#editorText'),
    editorDownload: $('#editorDownload'),
    editorSave: $('#editorSave')
  };

  const STEPS = ['display', 'audio', 'stream', 'proxy', 'console', 'game'];
  const VIEWS = ['connect', 'session', 'installations', 'files', 'settings', 'help'];
  const KEY_FOR_VIEW = { 1: 'connect', 2: 'session', 3: 'installations', 4: 'files', 5: 'settings', 6: 'help' };

  const DEFAULT_PREFS = {
    autoConnect: true,
    pollMs: 4000,
    motion: true,
    theme: 'light',
    logAuto: true
  };

  const state = {
    base: '',
    url: '',
    key: '',
    connected: false,
    demo: false,
    demoRunning: false,
    demoStage: 0,
    status: null,
    config: null,
    configError: '',
    probe: null,
    view: 'connect',
    pollTimer: 0,
    pollBusy: false,
    lastPollOk: 0,
    consoleMissing: false,
    warnedError: false,
    logTimer: 0,
    logName: 'minecraft',
    files: { root: 'repo', path: '', entries: [], loading: false, error: '' },
    editor: { root: 'repo', path: '', kind: 'text', size: 0 },
    prefs: { ...DEFAULT_PREFS }
  };

  /* ----------------------------------------------------------- storage --- */
  function loadState() {
    let raw = null;
    try {
      raw = localStorage.getItem(STORAGE_KEY);
    } catch (_) {
      return;
    }
    if (!raw) return;
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') {
        state.url = typeof parsed.url === 'string' ? parsed.url : '';
        state.key = typeof parsed.key === 'string' ? parsed.key : '';
        state.prefs = { ...DEFAULT_PREFS, ...(parsed.prefs || {}) };
      }
    } catch (_) {
      /* ignore corrupt storage */
    }
  }

  function saveState() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ url: state.url, key: state.key, prefs: state.prefs }));
      renderStorageNote();
    } catch (_) {
      /* preferences just do not stick */
    }
  }

  function renderStorageNote() {
    let bytes = 0;
    try {
      bytes = (localStorage.getItem(STORAGE_KEY) || '').length;
    } catch (_) {
      el.storageNote.textContent = 'localStorage is unavailable here, so nothing is saved.';
      return;
    }
    el.storageNote.textContent = bytes
      ? `Stored locally: ${bytes} bytes. The action key never leaves this device.`
      : 'Nothing stored yet.';
  }

  /* ------------------------------------------------------------- utils --- */
  function formatUptime(seconds) {
    const total = Math.max(0, Math.floor(Number(seconds) || 0));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m`;
    if (m > 0) return `${m}m ${String(s).padStart(2, '0')}s`;
    return `${s}s`;
  }

  function formatBytes(bytes) {
    const value = Number(bytes) || 0;
    if (value < 1024) return `${value} B`;
    if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
    if (value < 1024 * 1024 * 1024) return `${(value / (1024 * 1024)).toFixed(1)} MB`;
    return `${(value / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  function formatDate(seconds) {
    if (!seconds) return '—';
    try {
      return new Date(seconds * 1000).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    } catch (_) {
      return '—';
    }
  }

  function withTimeout(ms) {
    if (typeof AbortSignal !== 'undefined' && AbortSignal.timeout) return AbortSignal.timeout(ms);
    const controller = new AbortController();
    setTimeout(() => controller.abort(), ms);
    return controller.signal;
  }

  function toast(message, kind = 'ok', ms = 4200) {
    const node = document.createElement('div');
    node.className = 'toast';
    node.dataset.kind = kind;
    node.textContent = message;
    el.toastStack.appendChild(node);
    setTimeout(() => {
      node.classList.add('is-out');
      setTimeout(() => node.remove(), 240);
    }, ms);
  }

  function confirmAction(title, body, okLabel) {
    if (!el.confirmDialog || typeof el.confirmDialog.showModal !== 'function') {
      return Promise.resolve(window.confirm(`${title}\n\n${body}`));
    }
    el.confirmTitle.textContent = title;
    el.confirmBody.textContent = body;
    el.confirmOk.textContent = okLabel || 'Continue';
    el.confirmDialog.returnValue = '';
    el.confirmDialog.showModal();
    return new Promise((resolve) => {
      const onClose = () => {
        el.confirmDialog.removeEventListener('close', onClose);
        resolve(el.confirmDialog.returnValue === 'confirm');
      };
      el.confirmDialog.addEventListener('close', onClose);
    });
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (_) {
      try {
        const area = document.createElement('textarea');
        area.value = text;
        area.style.position = 'fixed';
        area.style.opacity = '0';
        document.body.appendChild(area);
        area.select();
        const ok = document.execCommand('copy');
        area.remove();
        return ok;
      } catch (_) {
        return false;
      }
    }
  }

  function basename(path) {
    const parts = String(path || '').split('/');
    return parts[parts.length - 1] || path;
  }

  function joinPath(path, name) {
    return path ? `${path}/${name}` : name;
  }

  /* --------------------------------------------------------- url parse --- */
  function fromCodespaceName(name, port, note) {
    const clean = String(name || '').trim().replace(/\/+$/, '');
    if (!/^[A-Za-z0-9][A-Za-z0-9-]{1,}$/.test(clean)) {
      return { ok: false, error: 'That does not look like a codespace name.' };
    }
    const host = `${clean}-${port}.app.github.dev`;
    return { ok: true, base: `https://${host}`, host, port, codespace: clean, note: note || '' };
  }

  function parseTarget(raw) {
    const text = String(raw || '').trim();
    if (!text) return { ok: false, error: 'Paste a codespace URL first.' };

    const ghLink = text.match(/^(?:https?:\/\/)?(?:www\.)?github\.com\/codespaces\/([A-Za-z0-9-]+)/i);
    if (ghLink) return fromCodespaceName(ghLink[1], PROXY_PORT, 'Read from a github.com/codespaces link.');

    let url = null;
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) {
      try {
        url = new URL(text);
      } catch (_) {
        return { ok: false, error: 'That URL could not be parsed.' };
      }
    } else if (/^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?([/?#]|$)/i.test(text)) {
      try {
        url = new URL(`http://${text}`);
      } catch (_) {
        return { ok: false, error: 'That URL could not be parsed.' };
      }
    } else if (/^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(:\d+)?([/?#]|$)/.test(text)) {
      try {
        url = new URL(`https://${text}`);
      } catch (_) {
        return { ok: false, error: 'That URL could not be parsed.' };
      }
    }

    if (!url) {
      const name = text.replace(/\/+$/, '');
      const withPort = name.match(/^(.*)-(\d{4,5})$/);
      if (withPort) return fromCodespaceName(withPort[1], Number(withPort[2]));
      if (/^[A-Za-z0-9][A-Za-z0-9-]{1,}$/.test(name)) {
        return fromCodespaceName(name, PROXY_PORT, 'Treated as a codespace name.');
      }
      return { ok: false, error: 'Paste a full URL, a codespace name, or a github.com/codespaces link.' };
    }

    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return { ok: false, error: 'Only http(s) URLs can host a stream.' };
    }

    const port = url.port ? Number(url.port) : url.protocol === 'https:' ? 443 : 80;
    const ghHost = url.hostname.match(/^(.+)-(\d{2,5})\.app\.github\.dev$/i);

    if (ghHost) {
      const codespace = ghHost[1];
      const detectedPort = Number(ghHost[2]);
      const base = `${url.protocol}//${url.hostname}`;
      let note = '';
      let fixBase = '';
      if (detectedPort !== PROXY_PORT) {
        note = `That is port ${detectedPort}. Glide's gateway lives on ${PROXY_PORT}.`;
        fixBase = `${url.protocol}//${codespace}-${PROXY_PORT}.app.github.dev`;
      }
      return { ok: true, base, host: url.hostname, port: detectedPort, codespace, note, fixBase };
    }

    return {
      ok: true,
      base: url.origin,
      host: url.hostname,
      port,
      codespace: '',
      note:
        url.hostname === 'localhost' || url.hostname.startsWith('127.')
          ? 'Local target.'
          : ''
    };
  }

  /* ------------------------------------------------------------- probe --- */
  async function readJson(response) {
    try {
      return await response.json();
    } catch (_) {
      return null;
    }
  }

  async function probeTarget(target) {
    const started = performance.now();
    const steps = [
      { key: 'url', label: 'URL parsed', state: 'ok', meta: `${target.host}:${target.port}` },
      { key: 'port', label: 'Codespace port answers', state: 'run', meta: '' },
      { key: 'console', label: 'Glide console responds', state: 'idle', meta: '' },
      { key: 'stream', label: 'Stream gateway is ready', state: 'idle', meta: '' },
      { key: 'game', label: 'Minecraft is running', state: 'idle', meta: '' }
    ];
    const finish = (kind, extra = {}) => ({
      kind,
      target,
      latency: Math.round(performance.now() - started),
      steps,
      ...extra
    });

    let response = null;
    let error = null;
    try {
      response = await fetch(`${target.base}/glide/status`, {
        signal: withTimeout(POLL_TIMEOUT),
        cache: 'no-store',
        credentials: 'omit'
      });
    } catch (err) {
      error = err;
    }

    if (response && response.ok) {
      const data = await readJson(response);
      steps[1].state = 'ok';
      steps[1].meta = `${Math.round(performance.now() - started)} ms`;
      steps[2].state = 'ok';
      steps[2].meta = data && data.app ? `${data.app.name} ${data.app.version}` : 'json';
      const streamReady = !!(data && data.stream && data.stream.gateway_ready);
      steps[3].state = streamReady ? 'ok' : 'fail';
      steps[3].meta = streamReady ? 'gateway up' : 'gateway down';
      const running = !!(data && data.minecraft && data.minecraft.ready);
      steps[4].state = running ? 'ok' : 'idle';
      steps[4].meta = running ? 'ready' : `stage: ${(data && data.stage && data.stage.key) || 'unknown'}`;
      return finish('console', { status: data });
    }

    if (response && (response.status === 404 || response.status === 405)) {
      steps[1].state = 'ok';
      steps[1].meta = 'reachable';
      steps[2].state = 'fail';
      steps[2].meta = `http ${response.status}`;
      return finish('no-console');
    }

    if (response && (response.status === 401 || response.status === 403)) {
      steps[1].state = 'fail';
      steps[1].meta = `http ${response.status}`;
      return finish('private', { code: response.status });
    }

    let reachable = false;
    try {
      await fetch(`${target.base}/`, {
        mode: 'no-cors',
        signal: withTimeout(POLL_TIMEOUT),
        cache: 'no-store',
        credentials: 'omit'
      });
      reachable = true;
    } catch (_) {
      reachable = false;
    }

    if (reachable) {
      steps[1].state = 'ok';
      steps[1].meta = 'reachable';
      steps[2].state = 'fail';
      steps[2].meta = 'unreadable';
      return finish('blocked', { error });
    }

    steps[1].state = 'fail';
    steps[1].meta = 'no answer';
    return finish('unreachable', { error });
  }

  /* ------------------------------------------------------------ render --- */
  function route(view, options = {}) {
    const target = VIEWS.includes(view) ? view : 'connect';
    state.view = target;
    if (options.push !== false && location.hash !== `#/${target}`) {
      history.pushState({ view: target }, '', `#/${target}`);
    }
    $$('.view').forEach((node) => node.classList.toggle('is-active', node.dataset.view === target));
    $$('.rail__item').forEach((button) => button.classList.toggle('is-active', button.dataset.nav === target));
    el.views.scrollTop = 0;

    if (target === 'session') {
      renderLogs();
      startLogTimer();
    } else {
      stopLogTimer();
    }
    if (target === 'installations') renderInstallations();
    if (target === 'settings') renderSettings();
    if (target === 'files') openFiles();
    if (target === 'session') {
      renderAll();
      renderLogs(true);
    }
  }

  function setStatusPill(kind, text) {
    el.statusPill.dataset.state = kind;
    el.statusText.textContent = text;
  }

  function statusKind(status) {
    if (state.demo) return state.demoRunning ? 'live' : 'booting';
    if (!state.connected) return 'idle';
    if (!status) return state.consoleMissing ? 'booting' : 'checking';
    const key = status.stage ? status.stage.key : '';
    if (key === 'error') return 'error';
    if (key === 'running') return 'live';
    if (key === 'stopped' || key === 'idle') return 'idle';
    return 'booting';
  }

  function currentStatus() {
    return state.demo ? demoStatus() : state.status;
  }

  function renderAll() {
    renderTopbar();
    renderStatus();
  }

  function renderTopbar() {
    el.hostChipText.textContent = state.base ? state.base.replace(/^https?:\/\//, '') : 'no codespace';
    el.demoChip.hidden = !state.demo;
    el.openStreamTop.disabled = !state.connected;
    const status = currentStatus();
    setStatusPill(
      statusKind(status),
      status && status.stage ? status.stage.label : state.connected ? (state.consoleMissing ? 'Stream only' : 'Connecting') : 'Idle'
    );
  }

  function renderStatus() {
    const status = currentStatus();

    if (!status) {
      el.sessionTag.textContent = state.connected ? 'checking' : 'idle';
      el.progressFill.style.width = '0%';
      el.statusLine.textContent = state.connected
        ? state.consoleMissing
          ? 'The stream is connected, but the Glide console API did not answer.'
          : 'Talking to the codespace…'
        : 'Connect a codespace to see live session telemetry.';
      renderSteps({});
      ['kvVersion', 'kvLoader', 'kvHeap', 'kvEncoder', 'kvUptime'].forEach((key) => {
        el[key].textContent = '—';
      });
      el.streamState.textContent = state.connected ? 'connecting' : 'not connected';
      return;
    }

    const stage = status.stage || {};
    const mc = status.minecraft || {};
    const stream = status.stream || {};
    const display = status.display || {};
    const session = status.session || {};

    el.sessionTag.textContent = stage.key || 'unknown';
    el.progressFill.style.width = `${Math.round(Math.max(0, Math.min(1, stage.progress || 0)) * 100)}%`;
    el.statusLine.textContent = stage.detail || 'Working…';
    renderSteps(status);

    el.kvVersion.textContent = mc.version || '—';
    el.kvLoader.textContent = mc.loader || '—';
    el.kvHeap.textContent = mc.xmx || '—';
    el.kvEncoder.textContent = stream.encoder ? `${stream.encoder} · ${stream.fps}fps` : '—';
    el.kvUptime.textContent = session.uptime_seconds ? formatUptime(session.uptime_seconds) : '—';

    const gateway = stream.gateway_ready ? 'gateway up' : stream.ready ? 'gateway down' : 'offline';
    el.streamState.textContent = stream.ready ? `live · ${gateway}` : 'not ready';
    el.openStreamBtn.disabled = !state.connected;
    el.openStreamTop.disabled = !state.connected;
  }

  function renderSteps(status) {
    const derived = deriveStepStates(status);
    $$('li', el.stepList).forEach((node) => {
      const value = derived[node.dataset.step] || 'idle';
      node.classList.toggle('is-done', value === 'done');
      node.classList.toggle('is-active', value === 'active');
      node.classList.toggle('is-error', value === 'error');
    });
  }

  function deriveStepStates(status) {
    if (!status) return {};
    const stageKey = status.stage ? status.stage.key : 'idle';
    const processes = (status.session && status.session.processes) || {};
    const stream = status.stream || {};
    const mc = status.minecraft || {};
    const stageMap = {
      display: 0,
      audio: 1,
      stream: 2,
      proxy: 3,
      console: 4,
      'stream-ready': 5,
      'game-booting': 5,
      running: 6,
      error: 6
    };
    const reach = stageMap[stageKey] == null ? 0 : stageMap[stageKey];
    const result = {};
    STEPS.forEach((key, index) => {
      if (index < reach) result[key] = 'done';
      else if (index === reach) result[key] = stageKey === 'error' ? 'error' : 'active';
      else result[key] = 'idle';
    });
    if (processes.xvfb) result.display = 'done';
    if (status.audio_ready) result.audio = 'done';
    if (stream.ready) result.stream = 'done';
    if (stream.gateway_ready) result.proxy = 'done';
    if (status.app) result.console = 'done';
    if (mc.ready) result.game = 'done';
    if (stageKey === 'error') result[STEPS[Math.min(reach, STEPS.length - 1)]] = 'error';
    return result;
  }

  /* ---------------------------------------------------------------- api --- */
  function apiUrl(path) {
    return `${state.base}/glide${path}`;
  }

  async function api(path, options = {}) {
    if (state.demo) throw new Error('Demo mode');
    if (!state.base) throw new Error('No codespace connected');
    const headers = { ...(options.headers || {}) };
    if (state.key) headers['X-Glide-Key'] = state.key;
    let body = options.body;
    if (options.json !== undefined) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(options.json);
    }
    const response = await fetch(apiUrl(path), {
      method: options.method || 'GET',
      headers,
      body,
      signal: withTimeout(options.timeout || API_TIMEOUT),
      credentials: 'omit',
      cache: 'no-store'
    });
    if (response.status === 401) throw new Error('This codespace wants the action key (Settings → Connection).');
    if (!response.ok) {
      let message = `HTTP ${response.status}`;
      try {
        const payload = await response.json();
        if (payload && payload.error) message = payload.error;
      } catch (_) {
        /* keep the status text */
      }
      throw new Error(message);
    }
    return options.raw ? response : response.json();
  }

  async function loadConfig(quiet) {
    if (state.demo) {
      state.config = demoConfig();
      state.configError = '';
      renderInstallations();
      renderSettings();
      return;
    }
    if (!state.connected) {
      state.config = null;
      renderInstallations();
      renderSettings();
      return;
    }
    try {
      state.config = await api('/config');
      state.configError = '';
    } catch (error) {
      state.config = null;
      state.configError = error.message;
      if (!quiet) toast(`Could not load installations: ${error.message}`, 'error', 6000);
    }
    renderInstallations();
    renderSettings();
  }

  /* ------------------------------------------------------- installations --- */
  function configValues() {
    return state.config && state.config.values ? state.config.values : null;
  }

  function loaderOptions() {
    const options = (state.config && state.config.options) || {};
    return options.loaders || ['vanilla', 'fabric', 'forge', 'quilt', 'neoforge', 'legacy-fabric', 'legacy-forge'];
  }

  function renderInstallations() {
    const connected = state.connected;
    el.instEmpty.hidden = connected;
    el.instBody.hidden = !connected;
    if (!connected) return;

    const values = configValues();
    el.instState.textContent = values ? 'ready' : state.configError ? 'error' : 'loading';

    if (!values) {
      if (state.configError) el.instModDir.textContent = state.configError;
      return;
    }

    el.instCurrentVersion.textContent = values.version || '—';
    el.instCurrentLoader.textContent = values.loader || '—';
    el.instCurrentHeap.textContent = values.xmx || '—';
    const mods = state.config.mods || [];
    el.instCurrentMods.textContent = String(mods.length);
    el.instModDir.textContent = state.config.mod_dir || '';

    el.instVersion.value = values.version || '';
    el.instHeap.value = values.xmx || '4G';
    if (!Array.from(el.instHeap.options).some((option) => option.value === values.xmx)) {
      const custom = document.createElement('option');
      custom.value = values.xmx;
      custom.textContent = values.xmx;
      el.instHeap.appendChild(custom);
      el.instHeap.value = values.xmx;
    }

    const loadedLoader = values.loader || 'fabric';
    if (!el.instLoader.dataset.filled) {
      el.instLoader.innerHTML = loaderOptions()
        .map((name) => `<option value="${name}">${name}</option>`)
        .join('');
      el.instLoader.dataset.filled = '1';
    }
    el.instLoader.value = loadedLoader;

    const versions = (state.config.options && state.config.options.versions) || [];
    el.versionOptions.innerHTML = versions.map((name) => `<option value="${name}"></option>`).join('');

    renderMods(mods, values);
  }

  function renderMods(mods, values) {
    el.modCount.textContent = String(mods.length);
    el.modTarget.textContent = values ? `${values.version} · ${values.loader}` : '—';
    el.modList.innerHTML = '';
    if (!mods.length) {
      const empty = document.createElement('li');
      empty.className = 'filelist__empty';
      empty.textContent = 'No mods yet for this installation.';
      el.modList.appendChild(empty);
      return;
    }
    mods.forEach((mod) => {
      const row = document.createElement('li');
      row.className = 'filerow filerow--mod';
      const name = document.createElement('span');
      name.className = 'filerow__name';
      name.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3h8l4 4v14H6z M14 3v5h5"/></svg>`;
      const label = document.createElement('span');
      label.textContent = mod.name;
      name.appendChild(label);
      const size = document.createElement('span');
      size.className = 'filerow__meta';
      size.textContent = formatBytes(mod.size);
      const action = document.createElement('button');
      action.className = 'btn btn--tiny btn--danger';
      action.type = 'button';
      action.textContent = 'Remove';
      action.addEventListener('click', async () => {
        const ok = await confirmAction('Remove this mod?', `${mod.name} is deleted from the codespace.`, 'Remove');
        if (!ok) return;
        try {
          await api('/mods/delete', {
            method: 'POST',
            json: { version: values.version, loader: values.loader, name: mod.name }
          });
          toast('Mod removed. It applies on the next game restart.', 'ok');
          loadConfig(true);
        } catch (error) {
          toast(error.message, 'error');
        }
      });
      row.append(name, size, action);
      el.modList.appendChild(row);
    });
  }

  async function applyInstallation() {
    const version = el.instVersion.value.trim();
    const loader = el.instLoader.value;
    const xmx = el.instHeap.value;
    if (!version) {
      toast('Pick a Minecraft version.', 'warn');
      return;
    }
    el.instApply.disabled = true;
    try {
      const payload = await api('/config', {
        method: 'POST',
        json: { values: { version, loader, xmx }, restart: 'game' }
      });
      state.config = payload.config;
      toast(`Switching to ${version} (${loader}). Minecraft restarts now.`, 'ok', 6000);
      renderInstallations();
      setTimeout(pollOnce, 800);
      setTimeout(pollOnce, 2600);
    } catch (error) {
      toast(error.message, 'error', 6000);
    } finally {
      el.instApply.disabled = false;
    }
  }

  async function uploadMods(fileList) {
    const files = Array.from(fileList || []).filter((file) => /\.(jar|zip)$/i.test(file.name));
    if (!files.length) {
      toast('Only .jar and .zip mods can be uploaded.', 'warn');
      return;
    }
    const values = configValues();
    if (!values) {
      toast('Installations are not loaded yet.', 'warn');
      return;
    }
    if (state.demo) {
      toast('Demo mode: uploads are disabled.', 'warn');
      return;
    }
    el.modUploadState.hidden = false;
    for (let index = 0; index < files.length; index += 1) {
      const file = files[index];
      el.modUploadState.textContent = `Uploading ${index + 1} of ${files.length}: ${file.name}`;
      try {
        await api(`/mods/upload?version=${encodeURIComponent(values.version)}&loader=${encodeURIComponent(values.loader)}&name=${encodeURIComponent(file.name)}`, {
          method: 'POST',
          body: file,
          timeout: 10 * 60 * 1000,
          headers: { 'Content-Type': 'application/octet-stream' }
        });
      } catch (error) {
        toast(`${file.name}: ${error.message}`, 'error', 6000);
      }
    }
    el.modUploadState.textContent = `Uploaded ${files.length} file(s). They apply on the next game restart.`;
    toast('Mods uploaded. Restart the game to load them.', 'ok');
    loadConfig(true);
  }

  /* -------------------------------------------------------------- files --- */
  function fileRootLabel() {
    return el.fileRoot.value === 'minecraft' ? 'Minecraft data' : 'Repository';
  }

  async function openFiles() {
    el.fileEmpty.hidden = state.connected;
    el.fileBody.hidden = !state.connected;
    if (!state.connected) return;
    state.files.root = el.fileRoot.value;
    await loadFiles(state.files.path);
  }

  async function loadFiles(path) {
    state.files.root = el.fileRoot.value;
    state.files.path = path || '';
    state.files.error = '';
    if (state.demo) {
      state.files.entries = demoFiles(state.files.root, state.files.path);
      renderFiles();
      return;
    }
    try {
      const data = await api(
        `/files?root=${encodeURIComponent(state.files.root)}&path=${encodeURIComponent(state.files.path)}`
      );
      state.files.entries = data.entries || [];
      state.files.path = data.path || '';
      state.files.rootLabel = data.root_label || fileRootLabel();
    } catch (error) {
      state.files.entries = [];
      state.files.error = error.message;
    }
    renderFiles();
  }

  function renderFiles() {
    el.fileEmpty.hidden = state.connected;
    el.fileBody.hidden = !state.connected;
    if (!state.connected) return;

    el.breadcrumb.innerHTML = '';
    const rootButton = document.createElement('button');
    rootButton.type = 'button';
    rootButton.className = 'crumb';
    rootButton.textContent = state.files.rootLabel || fileRootLabel();
    rootButton.addEventListener('click', () => loadFiles(''));
    el.breadcrumb.appendChild(rootButton);

    const parts = state.files.path ? state.files.path.split('/') : [];
    let walk = '';
    parts.forEach((part) => {
      walk = joinPath(walk, part);
      const target = walk;
      const sep = document.createElement('span');
      sep.className = 'crumb__sep';
      sep.textContent = '/';
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'crumb';
      button.textContent = part;
      button.addEventListener('click', () => loadFiles(target));
      el.breadcrumb.append(sep, button);
    });

    el.fileTable.innerHTML = '';
    if (state.files.error) {
      const error = document.createElement('p');
      error.className = 'filetable__empty';
      error.textContent = state.files.error;
      el.fileTable.appendChild(error);
      return;
    }
    if (!state.files.entries.length) {
      const empty = document.createElement('p');
      empty.className = 'filetable__empty';
      empty.textContent = 'This folder is empty.';
      el.fileTable.appendChild(empty);
      return;
    }

    const head = document.createElement('div');
    head.className = 'filerow filerow--head';
    head.innerHTML = '<span>name</span><span>size</span><span>changed</span><span></span>';
    el.fileTable.appendChild(head);

    state.files.entries.forEach((entry) => {
      const row = document.createElement('div');
      row.className = 'filerow';

      const name = document.createElement('button');
      name.type = 'button';
      name.className = 'filerow__name';
      name.innerHTML = entry.type === 'dir'
        ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7a1 1 0 0 1 1-1h5l2 2h9a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/></svg>'
        : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3h8l4 4v14H6z M14 3v5h5"/></svg>';
      const label = document.createElement('span');
      label.textContent = entry.name;
      name.appendChild(label);
      name.addEventListener('click', () => {
        if (entry.type === 'dir') loadFiles(joinPath(state.files.path, entry.name));
        else openFile(joinPath(state.files.path, entry.name));
      });

      const size = document.createElement('span');
      size.className = 'filerow__meta';
      size.textContent = entry.type === 'dir' ? '—' : formatBytes(entry.size);

      const modified = document.createElement('span');
      modified.className = 'filerow__meta';
      modified.textContent = formatDate(entry.modified);

      const actions = document.createElement('span');
      actions.className = 'filerow__actions';
      if (entry.type === 'file') {
        const download = document.createElement('button');
        download.type = 'button';
        download.className = 'btn btn--tiny';
        download.textContent = 'Download';
        download.addEventListener('click', () => downloadFile(joinPath(state.files.path, entry.name)));
        actions.appendChild(download);
      }
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'btn btn--tiny btn--danger';
      remove.textContent = 'Delete';
      remove.addEventListener('click', async () => {
        const ok = await confirmAction(
          `Delete ${entry.name}?`,
          entry.type === 'dir' ? 'The folder and everything inside it are deleted.' : 'The file is deleted from the codespace.',
          'Delete'
        );
        if (!ok) return;
        try {
          await api('/files/delete', {
            method: 'POST',
            json: { root: state.files.root, path: joinPath(state.files.path, entry.name) }
          });
          toast('Deleted.', 'ok');
          loadFiles(state.files.path);
        } catch (error) {
          toast(error.message, 'error');
        }
      });
      actions.appendChild(remove);

      row.append(name, size, modified, actions);
      el.fileTable.appendChild(row);
    });
  }

  function downloadFile(path) {
    if (state.demo) {
      toast('Demo mode: downloads are disabled.', 'warn');
      return;
    }
    const url = apiUrl(`/files/download?root=${encodeURIComponent(state.files.root)}&path=${encodeURIComponent(path)}`);
    const link = document.createElement('a');
    link.href = url;
    link.target = '_blank';
    link.rel = 'noopener';
    link.click();
  }

  async function openFile(path) {
    if (state.demo) {
      openEditor({ kind: 'text', path, text: 'Demo preview. Connect a codespace to edit real files.' });
      return;
    }
    try {
      const data = await api(`/files/read?root=${encodeURIComponent(state.files.root)}&path=${encodeURIComponent(path)}`);
      openEditor(data);
    } catch (error) {
      toast(error.message, 'error');
    }
  }

  function openEditor(data) {
    state.editor = {
      root: state.files.root,
      path: data.path || state.files.path,
      kind: data.kind || 'text',
      size: data.size || 0
    };
    el.editorTitle.textContent = basename(state.editor.path);
    el.editorPath.textContent = `${fileRootLabel()} / ${state.editor.path}`;
    el.editorText.value = data.kind === 'text' ? data.text || '' : 'Binary file — download it to inspect the contents.';
    el.editorText.disabled = data.kind !== 'text';
    el.editorSave.hidden = data.kind !== 'text';
    if (typeof el.editorDialog.showModal === 'function') el.editorDialog.showModal();
  }

  async function saveEditor() {
    if (!state.editor.path) return;
    try {
      await api('/files/save', {
        method: 'POST',
        json: { root: state.editor.root, path: state.editor.path, text: el.editorText.value }
      });
      toast('Saved.', 'ok');
      el.editorDialog.close();
      loadFiles(state.files.path);
    } catch (error) {
      toast(error.message, 'error');
    }
  }

  async function uploadToCurrentDir(fileList) {
    const files = Array.from(fileList || []);
    if (!files.length) return;
    el.fileUploadState.hidden = false;
    for (let index = 0; index < files.length; index += 1) {
      const file = files[index];
      el.fileUploadState.textContent = `Uploading ${index + 1} of ${files.length}: ${file.name}`;
      try {
        await api(
          `/files/upload?root=${encodeURIComponent(state.files.root)}&path=${encodeURIComponent(state.files.path)}&name=${encodeURIComponent(file.name)}`,
          { method: 'POST', body: file, timeout: 10 * 60 * 1000, headers: { 'Content-Type': 'application/octet-stream' } }
        );
      } catch (error) {
        toast(`${file.name}: ${error.message}`, 'error', 6000);
      }
    }
    el.fileUploadState.textContent = `Uploaded ${files.length} file(s).`;
    loadFiles(state.files.path);
  }

  async function makeFolder() {
    const name = window.prompt('Folder name');
    if (!name) return;
    if (name.includes('/') || name.includes('\\')) {
      toast('Folder names cannot contain slashes.', 'warn');
      return;
    }
    try {
      await api('/files/mkdir', {
        method: 'POST',
        json: { root: state.files.root, path: joinPath(state.files.path, name) }
      });
      loadFiles(state.files.path);
    } catch (error) {
      toast(error.message, 'error');
    }
  }

  /* ----------------------------------------------------------- settings --- */
  function inferProfile(fps, bitrate) {
    if (Number(bitrate) >= 10000) return 'high';
    if (Number(bitrate) <= 3000 || Number(fps) <= 30) return 'low';
    return 'medium';
  }

  function setProfile(preset) {
    const values = { low: [30, 2500], medium: [60, 6000], high: [60, 12000] }[preset];
    if (!values) return;
    el.setFps.value = String(values[0]);
    el.setBitrate.value = String(values[1]);
    $$('#profileGroup button').forEach((button) => button.classList.toggle('is-active', button.dataset.profile === preset));
  }

  function renderSettings() {
    el.settingsUrl.value = state.url;
    el.settingsKey.value = state.key;
    el.settingsAuto.checked = state.prefs.autoConnect;
    el.settingsPoll.value = String(state.prefs.pollMs);
    el.settingsMotion.checked = state.prefs.motion;
    renderStorageNote();

    const values = configValues();
    el.settingsEmpty.hidden = !!values;
    el.saveStream.disabled = !values;
    el.saveMinecraft.disabled = !values;
    if (!values) return;

    const encoders = (state.config.options && state.config.options.encoders) || ['h264enc'];
    if (!el.setEncoder.dataset.filled) {
      el.setEncoder.innerHTML = encoders.map((name) => `<option value="${name}">${name}</option>`).join('');
      el.setEncoder.dataset.filled = '1';
    }
    el.setResolution.value = values.resolution;
    if (!Array.from(el.setResolution.options).some((option) => option.value === values.resolution)) {
      const custom = document.createElement('option');
      custom.value = values.resolution;
      custom.textContent = values.resolution.replace('x', ' × ');
      el.setResolution.appendChild(custom);
      el.setResolution.value = values.resolution;
    }
    el.setBitrate.value = String(values.bitrate);
    el.setFps.value = String(values.fps);
    el.setEncoder.value = values.encoder;
    el.setDashboard.checked = !!values.dashboard;
    el.setAudio.checked = !!values.audio;
    el.setAuthMode.value = values.auth_mode;
    el.setUsername.value = values.username;
    el.setClientId.value = values.client_id || '';
    $$('#profileGroup button').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.profile === inferProfile(values.fps, values.bitrate));
    });
  }

  async function saveStream() {
    const values = configValues();
    if (!values) return;
    const next = {
      resolution: el.setResolution.value,
      fps: Number(el.setFps.value),
      bitrate: Number(el.setBitrate.value),
      encoder: el.setEncoder.value,
      dashboard: el.setDashboard.checked,
      audio: el.setAudio.checked
    };
    const resolutionChanged = next.resolution !== values.resolution;
    if (resolutionChanged) {
      const ok = await confirmAction(
        'Restart the session?',
        'The virtual display has to be recreated for a new resolution, so the whole session restarts.',
        'Save & restart'
      );
      if (!ok) return;
    }
    await saveConfig({ values: next, restart: resolutionChanged ? 'session' : 'stream' }, 'Stream settings saved.');
  }

  async function saveMinecraft() {
    const values = configValues();
    if (!values) return;
    await saveConfig(
      {
        values: {
          auth_mode: el.setAuthMode.value,
          username: el.setUsername.value,
          client_id: el.setClientId.value.trim()
        },
        restart: 'game'
      },
      'Account settings saved. Minecraft restarts now.'
    );
  }

  async function saveConfig(payload, message) {
    if (state.demo) {
      toast('Demo mode: saving is disabled.', 'warn');
      return;
    }
    try {
      const result = await api('/config', { method: 'POST', json: payload });
      state.config = result.config;
      toast(message, 'ok', 5000);
      renderInstallations();
      renderSettings();
      setTimeout(pollOnce, 700);
      setTimeout(pollOnce, 2400);
    } catch (error) {
      toast(error.message, 'error', 6000);
    }
  }

  /* -------------------------------------------------------------- logs --- */
  function startLogTimer() {
    stopLogTimer();
    if (!state.prefs.logAuto || state.demo) return;
    state.logTimer = window.setInterval(() => {
      if (!document.hidden && state.view === 'session') renderLogs(true);
    }, 3200);
  }

  function stopLogTimer() {
    if (state.logTimer) {
      clearInterval(state.logTimer);
      state.logTimer = 0;
    }
  }

  async function renderLogs(quiet) {
    const name = state.logName;
    if (state.demo) {
      el.logPre.textContent = demoLog(name);
      el.logStatus.textContent = 'demo';
      return;
    }
    if (!state.base) {
      el.logPre.textContent = 'Connect a codespace to read its logs.';
      el.logStatus.textContent = 'idle';
      return;
    }
    if (!quiet) el.logStatus.textContent = 'loading…';
    try {
      const response = await fetch(
        `${state.base}/glide/log?name=${encodeURIComponent(name)}&tail=400`,
        { signal: withTimeout(POLL_TIMEOUT), cache: 'no-store', credentials: 'omit' }
      );
      if (!response.ok) {
        el.logPre.textContent =
          response.status === 401 || response.status === 403
            ? 'The port is private, so the log cannot be read.'
            : `Log endpoint returned HTTP ${response.status}.`;
        el.logStatus.textContent = 'error';
        return;
      }
      const text = await response.text();
      const atBottom = el.logPre.scrollTop + el.logPre.clientHeight >= el.logPre.scrollHeight - 32;
      el.logPre.textContent = text || 'This log is empty.';
      if (atBottom) el.logPre.scrollTop = el.logPre.scrollHeight;
      el.logStatus.textContent = `${name} · ${new Date().toLocaleTimeString()}`;
    } catch (_) {
      el.logStatus.textContent = 'unreachable';
      if (!quiet) el.logPre.textContent = 'Could not reach the codespace console.';
    }
  }

  /* -------------------------------------------------------- connection --- */
  function setProbeUI(result, target) {
    el.probePanel.hidden = false;
    el.probeSteps.innerHTML = '';
    result.steps.forEach((step) => {
      const li = document.createElement('li');
      li.dataset.state = step.state;
      const dot = document.createElement('span');
      dot.className = 'dot';
      const label = document.createElement('span');
      label.textContent = step.label;
      const meta = document.createElement('span');
      meta.className = 'meta';
      meta.textContent = step.meta || '';
      li.append(dot, label, meta);
      el.probeSteps.appendChild(li);
    });
    el.probeLatency.hidden = false;
    el.probeLatency.textContent = `${result.latency} ms`;

    const kinds = {
      console: {
        title: 'Codespace found',
        sub: 'Console API, stream gateway and the session are reachable.',
        open: true
      },
      'no-console': {
        title: 'Stream answered, console did not',
        sub: 'The port is reachable but /glide/status returned nothing useful. The stream still works; controls and files will be limited.',
        open: true
      },
      blocked: {
        title: 'Port is reachable but unreadable',
        sub: 'That usually means the port is private. Keep it that way and open the stream in its own tab after connecting.',
        open: true
      },
      private: {
        title: 'The port asks for GitHub sign-in',
        sub: 'Private ports cannot be embedded; they open fine in their own tab while you are signed in to GitHub.',
        open: false
      },
      unreachable: {
        title: 'No answer from the codespace',
        sub: 'Check that the codespace is running and port 6080 is exposed, then try again.',
        open: false
      }
    };
    const info = kinds[result.kind] || kinds.unreachable;
    el.probeTitle.textContent = info.title;
    el.probeSub.textContent = target.note ? `${info.sub} ${target.note}` : info.sub;
    el.probeActions.hidden = false;
    el.probeOpenBtn.hidden = !info.open;
    el.probeOpenBtn.textContent = result.kind === 'console' ? 'Open session' : 'Connect anyway';
    el.probeOpenBtn.dataset.base = target.base;
    el.probeFixBtn.hidden = !target.fixBase;
    if (target.fixBase) {
      el.probeFixBtn.dataset.base = target.fixBase;
      el.probeFixBtn.textContent = `Use port ${PROXY_PORT}`;
    }
    el.probeTabBtn.hidden = result.kind !== 'private';
    el.probeTabBtn.dataset.base = target.base;

    if (result.kind === 'console' && result.status) {
      state.status = result.status;
      renderStatus();
    }
    if (result.kind === 'console' || result.kind === 'no-console' || result.kind === 'blocked') {
      state.url = target.base;
      saveState();
    }
  }

  async function connect(raw, options = {}) {
    const inlineKey = String(raw || '').match(/[#&?]key=([^&#\s]+)/);
    if (inlineKey) {
      try {
        state.key = decodeURIComponent(inlineKey[1]);
      } catch (_) {
        state.key = inlineKey[1];
      }
      saveState();
    }

    const target = parseTarget(raw);
    if (!target.ok) {
      if (!options.silent) toast(target.error, 'error');
      el.probePanel.hidden = false;
      el.probeTitle.textContent = 'That URL cannot be used';
      el.probeSub.textContent = target.error;
      el.probeSteps.innerHTML = '';
      el.probeActions.hidden = true;
      return false;
    }

    el.connectBtn.disabled = true;
    el.connectBtn.querySelector('span').textContent = 'Checking…';
    el.probePanel.hidden = false;
    el.probeTitle.textContent = 'Checking the codespace…';
    el.probeSub.textContent = 'Looking for the Glide console on this port.';
    el.probeLatency.hidden = true;
    el.probeSteps.innerHTML = '';
    el.probeActions.hidden = true;
    setStatusPill('checking', 'Checking');

    const result = await probeTarget(target);
    state.probe = result;
    setProbeUI(result, target);
    el.connectBtn.disabled = false;
    el.connectBtn.querySelector('span').textContent = 'Connect';

    if (result.kind === 'blocked') setStatusPill('error', 'Port unreadable');
    else if (result.kind === 'no-console') setStatusPill('booting', 'Stream only');

    if (result.kind === 'private' || result.kind === 'unreachable') {
      setStatusPill('error', result.kind === 'private' ? 'Port is private' : 'Unreachable');
      if (!options.silent) {
        toast(
          result.kind === 'private'
            ? 'The port is private. Use “Open in a new tab” while signed in to GitHub.'
            : 'No answer from the codespace. Is it running and is port 6080 exposed?',
          'error',
          7000
        );
      }
      return false;
    }

    if (options.autoOpen !== false) {
      if (result.kind === 'console' || result.kind === 'no-console' || (!options.silent && result.kind === 'blocked')) {
        openSession(target.base, result);
      }
    }
    return result.kind !== 'blocked' || !options.silent;
  }

  function openSession(base, probe) {
    state.consoleMissing = false;
    state.base = base;
    state.url = base;
    state.connected = true;
    state.config = null;
    saveState();
    el.codespaceInput.value = base;
    el.settingsUrl.value = base;
    if (probe && probe.kind === 'console') state.status = probe.status;
    route('session');
    renderAll();
    startPolling();
    pollOnce();
    loadConfig(true);
    setStatusPill('checking', 'Connecting');
    toast(`Connected to ${base.replace(/^https?:\/\//, '')}`, 'ok');
  }

  function disconnect() {
    stopPolling();
    state.connected = false;
    state.status = null;
    state.config = null;
    state.base = '';
    state.files = { root: 'repo', path: '', entries: [], loading: false, error: '' };
    el.logPre.textContent = 'Connect a codespace to read its logs.';
    el.streamState.textContent = 'not connected';
    renderAll();
    route('connect');
    toast('Disconnected.', 'warn');
  }

  /* ----------------------------------------------------------- polling --- */
  function startPolling() {
    stopPolling();
    if (!state.base) return;
    state.pollTimer = window.setInterval(() => {
      if (!document.hidden) pollOnce();
    }, state.prefs.pollMs);
  }

  function stopPolling() {
    if (state.pollTimer) {
      clearInterval(state.pollTimer);
      state.pollTimer = 0;
    }
  }

  async function pollOnce() {
    if (state.demo) {
      renderAll();
      return;
    }
    if (!state.base || state.pollBusy) return;
    state.pollBusy = true;
    try {
      const response = await fetch(`${state.base}/glide/status`, {
        signal: withTimeout(POLL_TIMEOUT),
        cache: 'no-store',
        credentials: 'omit'
      });
      if (response.status === 401 || response.status === 403) {
        setStatusPill('error', 'Port is private');
        state.status = null;
        return;
      }
      if (response.status === 404 || response.status === 405) {
        state.consoleMissing = true;
        setStatusPill('booting', 'Stream only');
        stopPolling();
        return;
      }
      if (!response.ok) {
        setStatusPill('error', 'Console unavailable');
        state.status = null;
        return;
      }
      const data = await readJson(response);
      if (data) {
        state.status = data;
        state.lastPollOk = Date.now();
        renderTopbar();
        renderStatus();
        if (data.stage && data.stage.key === 'error' && !state.warnedError) {
          state.warnedError = true;
          toast(data.stage.detail || 'The codespace reported an error.', 'error', 6000);
        }
        if (data.stage && data.stage.key !== 'error') state.warnedError = false;
      }
    } catch (_) {
      if (!state.lastPollOk || Date.now() - state.lastPollOk > 15000) setStatusPill('error', 'Unreachable');
    } finally {
      state.pollBusy = false;
    }
  }

  /* ------------------------------------------------------------ actions --- */
  const ACTION_LABELS = {
    'restart-game': 'Restarting Minecraft',
    'restart-stream': 'Restarting the stream',
    'restart-session': 'Restarting the whole session',
    stop: 'Stopping the session'
  };

  async function postAction(action, args = {}) {
    if (state.demo) {
      toast('Demo mode: controls are disabled.', 'warn');
      return false;
    }
    if (!state.base || !state.connected) {
      toast('Connect a codespace first.', 'warn');
      return false;
    }
    try {
      await api('/action', { method: 'POST', json: { action, args } });
      toast(ACTION_LABELS[action] || 'Action sent.', 'ok');
      setTimeout(pollOnce, 900);
      setTimeout(pollOnce, 3000);
      return true;
    } catch (error) {
      toast(error.message, 'error', 6000);
      return false;
    }
  }

  async function runAction(action) {
    const needsConfirm = action === 'stop' || action === 'restart-session';
    if (needsConfirm) {
      const ok = await confirmAction(
        action === 'stop' ? 'Stop the session?' : 'Restart everything?',
        action === 'stop'
          ? 'Minecraft, the stream and the display are stopped. Worlds stay in the codespace.'
          : 'The display, stream and Minecraft restart. The world is saved on the way down.',
        action === 'stop' ? 'Stop session' : 'Restart session'
      );
      if (!ok) return;
    }
    await postAction(action);
  }

  /* -------------------------------------------------------------- demo --- */
  const DEMO_STAGES = [
    { key: 'display', label: 'Starting display', detail: 'starting virtual display 1280x720', progress: 0.12 },
    { key: 'audio', label: 'Starting audio', detail: 'starting pulseaudio', progress: 0.2 },
    { key: 'stream', label: 'Starting stream', detail: 'starting Selkies on :8080', progress: 0.45 },
    { key: 'proxy', label: 'Opening the gateway', detail: 'starting nginx on :6080', progress: 0.6 },
    { key: 'game-booting', label: 'Starting Minecraft', detail: 'Downloading Minecraft', progress: 0.8 },
    { key: 'running', label: 'Running', detail: 'Minecraft is running', progress: 1 }
  ];

  function demoStatus() {
    const index = state.demoRunning ? DEMO_STAGES.length - 1 : state.demoStage % DEMO_STAGES.length;
    const stage = DEMO_STAGES[index];
    const now = Math.floor(Date.now() / 1000);
    const running = stage.key === 'running';
    const lines = [
      '[14:02:11] [main/INFO]: Loading Minecraft 1.21.5 with Fabric Loader 0.16.9',
      '[14:02:12] [Render thread/INFO]: OpenGL Vendor: Mesa/X.org',
      '[14:02:13] [Render thread/INFO]: Renderer: llvmpipe (LLVM 17.0.6, 256 bits)',
      '[14:02:15] [Render thread/INFO]: Backend library: LWJGL version 3.3.3+5',
      running ? '[14:02:18] [Render thread/INFO]: Sound engine started' : '[14:02:16] [Render thread/INFO]: Reloading resource manager: vanilla',
      running ? 'GLIDE_READY=true' : `GLIDE_STAGE=${stage.key.replace('-', '_')}`
    ];
    return {
      ok: true,
      app: { name: 'glide-console', version: '3.1' },
      now,
      key_required: false,
      host: {
        hostname: 'demo',
        codespace: 'glide-demo-1234',
        domain: 'app.github.dev',
        public_url: 'https://glide-demo-1234-6080.app.github.dev',
        repo: '/workspaces/Glide'
      },
      stage: {
        key: stage.key,
        label: stage.label,
        detail: stage.detail,
        progress: stage.progress,
        updated_at: now,
        started_at: now - 312
      },
      minecraft: {
        version: '1.21.5',
        loader: 'fabric',
        xmx: '4G',
        auth_mode: 'offline',
        pid: index >= 4 ? 4242 : null,
        running: index >= 4,
        ready: running,
        log_stage: running ? 'minecraft-running' : 'minecraft-download',
        resolution: '1280x720'
      },
      stream: {
        ready: index >= 2,
        gateway_ready: index >= 3,
        port: 8080,
        gateway_port: 6080,
        encoder: 'h264enc',
        fps: 60,
        bitrate: 6000,
        audio: true,
        dashboard: true
      },
      audio_ready: index >= 1,
      display: { server: 'Xvfb', display: ':99', width: 1280, height: 720 },
      session: {
        up: true,
        uptime_seconds: 312,
        processes: { xvfb: index >= 1, selkies: index >= 2, console: true, minecraft: index >= 4 }
      },
      actions: ['restart-game', 'restart-stream', 'restart-session', 'stop'],
      log_tail: lines
    };
  }

  function demoConfig() {
    return {
      ok: true,
      values: {
        version: '1.21.5',
        loader: 'fabric',
        xmx: '4G',
        resolution: '1280x720',
        fps: 60,
        bitrate: 6000,
        encoder: 'h264enc',
        dashboard: true,
        audio: true,
        auth_mode: 'offline',
        username: 'GlidePlayer'
      },
      options: {
        loaders: ['vanilla', 'fabric', 'legacy-fabric', 'forge', 'legacy-forge', 'quilt', 'neoforge'],
        encoders: ['h264enc', 'h265enc', 'vp8enc', 'vp9enc', 'av1enc', 'h264enc-striped', 'jpeg'],
        versions: ['1.21.5', '1.21.4', '1.21.1', '1.20.1', '1.19.4', '1.18.2', '1.16.5', '1.12.2']
      },
      mods: [
        { name: 'sodium-fabric-0.6.9.jar', size: 2260992, modified: 1760000000 },
        { name: 'lithium-fabric-0.15.3.jar', size: 771072, modified: 1760000000 },
        { name: 'ferritecore-7.0.2.jar', size: 120832, modified: 1760000000 }
      ],
      mod_dir: 'Client/mods/1.21.5/fabric'
    };
  }

  function demoFiles(root, path) {
    const repo = {
      '': [{ name: 'Client', type: 'dir' }, { name: 'Html', type: 'dir' }, { name: 'README.md', type: 'file', size: 11200 }, { name: 'serve.py', type: 'file', size: 1900 }],
      Client: [{ name: 'mods', type: 'dir' }, { name: '26.2', type: 'dir' }, { name: 'scripts', type: 'dir' }],
      'Client/mods': [{ name: '1.21.5', type: 'dir' }],
      'Client/mods/1.21.5': [{ name: 'fabric', type: 'dir' }],
      'Client/mods/1.21.5/fabric': [{ name: 'sodium.jar', type: 'file', size: 2260992 }],
      Html: [{ name: 'app.js', type: 'file', size: 51000 }, { name: 'app.css', type: 'file', size: 44000 }, { name: 'index.html', type: 'file', size: 37000 }]
    };
    const minecraft = {
      '': [{ name: 'saves', type: 'dir' }, { name: 'options.txt', type: 'file', size: 2600 }, { name: 'servers.dat', type: 'file', size: 900 }],
      saves: [{ name: 'Glide World', type: 'dir' }]
    };
    const table = root === 'minecraft' ? minecraft : repo;
    return (table[path] || []).map((entry) => ({ modified: 1760000000, ...entry }));
  }

  function demoLog(name) {
    if (name === 'boot') {
      return [
        '===== glide boot (all) =====',
        '[glide] display ready: 1280x720 on :99',
        '[glide] audio ready: glide_game_sink',
        '[glide] stream ready on 127.0.0.1:8080',
        '[glide] proxy ready on :6080 -> :8080',
        '[glide] console API ready on 127.0.0.1:6081',
        '[glide] Minecraft launcher started'
      ].join('\n');
    }
    if (name === 'selkies') {
      return [
        'INFO selkies: starting websocket transport',
        'INFO selkies: encoder=h264enc framerate=60 bitrate=6000',
        'INFO selkies: display :99 1280x720',
        'INFO selkies: listening on 127.0.0.1:8080',
        'INFO selkies: client connected (1)'
      ].join('\n');
    }
    if (name === 'nginx') return 'nginx started\nwebsocket upgrade /api/websockets';
    if (name === 'console') return 'glide-console 3.1 listening on 127.0.0.1:6081';
    if (name === 'xvfb') return 'Xvfb :99 -screen 0 1280x720x24';
    return demoStatus().log_tail.join('\n');
  }

  function startDemo(running) {
    state.demo = true;
    state.demoRunning = !!running;
    state.connected = true;
    state.base = 'https://glide-demo-1234-6080.app.github.dev';
    state.url = state.base;
    el.codespaceInput.value = state.base;
    loadConfig(true);
    const demoHash = (location.hash || '').replace(/^#\/?/, '').split('&')[0];
    route(VIEWS.includes(demoHash) ? demoHash : 'session', { push: false });
    renderAll();
    renderLogs(true);
    if (!running) {
      setInterval(() => {
        state.demoStage += 1;
        if (state.demoStage >= DEMO_STAGES.length - 1) state.demoRunning = true;
        renderAll();
        if (state.view === 'installations' || state.view === 'settings') renderSettings();
      }, 3200);
    }
    toast('Demo preview: this shell is not connected to a codespace.', 'warn', 6000);
  }

  /* --------------------------------------------------------------- boot --- */
  function bind() {
    $$('[data-nav]').forEach((button) => {
      button.addEventListener('click', () => route(button.dataset.nav));
    });

    window.addEventListener('hashchange', () => {
      const view = (location.hash || '').replace(/^#\/?/, '').split('&')[0];
      if (VIEWS.includes(view) && view !== state.view) route(view, { push: false });
    });

    el.connectForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      const ok = await connect(el.codespaceInput.value.trim());
      if (!ok) el.codespaceInput.focus();
    });

    el.probeOpenBtn.addEventListener('click', () => {
      const base = el.probeOpenBtn.dataset.base || (state.probe && state.probe.target.base);
      if (base) openSession(base, state.probe);
    });
    el.probeFixBtn.addEventListener('click', () => {
      const base = el.probeFixBtn.dataset.base;
      if (base) {
        el.codespaceInput.value = base;
        connect(base);
      }
    });
    el.probeTabBtn.addEventListener('click', () => {
      const base = el.probeTabBtn.dataset.base;
      if (base) window.open(`${base}/`, '_blank', 'noopener,noreferrer');
    });

    el.themeToggle.addEventListener('click', () => {
      state.prefs.theme = state.prefs.theme === 'dark' ? 'light' : 'dark';
      saveState();
      applyAppearance();
    });

    $$('[data-action]').forEach((node) => {
      if (node.tagName === 'INPUT') return;
      node.addEventListener('click', () => runAction(node.dataset.action));
    });

    el.instRefresh.addEventListener('click', () => loadConfig());
    el.instApply.addEventListener('click', applyInstallation);
    el.modBrowse.addEventListener('click', () => el.modInput.click());
    el.modInput.addEventListener('change', () => {
      uploadMods(el.modInput.files);
      el.modInput.value = '';
    });
    ['dragenter', 'dragover'].forEach((eventName) => {
      el.modDrop.addEventListener(eventName, (event) => {
        event.preventDefault();
        el.modDrop.classList.add('is-over');
      });
    });
    ['dragleave', 'drop'].forEach((eventName) => {
      el.modDrop.addEventListener(eventName, (event) => {
        event.preventDefault();
        el.modDrop.classList.remove('is-over');
      });
    });
    el.modDrop.addEventListener('drop', (event) => uploadMods(event.dataTransfer.files));

    el.fileRoot.addEventListener('change', () => {
      state.files.path = '';
      loadFiles('');
    });
    el.fileRefresh.addEventListener('click', () => loadFiles(state.files.path));
    el.fileUpload.addEventListener('click', () => el.fileInput.click());
    el.fileInput.addEventListener('change', () => {
      uploadToCurrentDir(el.fileInput.files);
      el.fileInput.value = '';
    });
    el.fileMkdir.addEventListener('click', makeFolder);

    el.profileGroup.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-profile]');
      if (button) setProfile(button.dataset.profile);
    });
    el.saveStream.addEventListener('click', saveStream);
    el.saveMinecraft.addEventListener('click', saveMinecraft);

    el.logSelect.addEventListener('change', () => {
      state.logName = el.logSelect.value;
      renderLogs();
    });
    el.logAuto.addEventListener('change', () => {
      state.prefs.logAuto = el.logAuto.checked;
      saveState();
      if (state.prefs.logAuto) startLogTimer();
      else stopLogTimer();
    });
    el.logRefresh.addEventListener('click', () => renderLogs());
    el.logCopy.addEventListener('click', async () => {
      const ok = await copyText(el.logPre.textContent || '');
      toast(ok ? 'Log copied.' : 'Clipboard blocked by the browser.', ok ? 'ok' : 'warn');
    });

    el.settingsUrl.addEventListener('change', () => {
      state.url = el.settingsUrl.value.trim();
      saveState();
    });
    el.settingsKey.addEventListener('change', () => {
      state.key = el.settingsKey.value.trim();
      saveState();
      toast('Action key saved in this browser.', 'ok', 2400);
    });
    el.settingsAuto.addEventListener('change', () => {
      state.prefs.autoConnect = el.settingsAuto.checked;
      saveState();
    });
    el.settingsPoll.addEventListener('change', () => {
      state.prefs.pollMs = Number(el.settingsPoll.value) || 4000;
      saveState();
      if (state.connected) startPolling();
    });
    el.settingsMotion.addEventListener('change', () => {
      state.prefs.motion = el.settingsMotion.checked;
      saveState();
      applyAppearance();
    });
    el.settingsForget.addEventListener('click', async () => {
      const ok = await confirmAction(
        'Forget saved data?',
        'The codespace URL, action key and preferences are removed from this browser.',
        'Forget'
      );
      if (!ok) return;
      try {
        localStorage.removeItem(STORAGE_KEY);
      } catch (_) {
        /* ignore */
      }
      state.url = '';
      state.key = '';
      state.prefs = { ...DEFAULT_PREFS };
      applyAppearance();
      renderSettings();
      toast('Saved data cleared.', 'ok');
    });

    el.editorSave.addEventListener('click', saveEditor);
    el.editorDownload.addEventListener('click', () => {
      if (state.editor.path) downloadFile(state.editor.path);
    });
    el.editorDialog.addEventListener('close', () => {
      state.editor.path = '';
    });

    el.demoChip.addEventListener('click', () => {
      state.demoRunning = true;
      renderAll();
    });

    document.addEventListener('keydown', (event) => {
      const tag = (event.target && event.target.tagName) || '';
      if (/^(INPUT|TEXTAREA|SELECT)$/.test(tag) || event.metaKey || event.ctrlKey || event.altKey) return;
      if (event.key === '?') {
        route('help');
        event.preventDefault();
      } else if (/^[1-6]$/.test(event.key)) {
        route(KEY_FOR_VIEW[event.key]);
        event.preventDefault();
      }
    });

    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) {
        pollOnce();
        if (state.view === 'session') renderLogs(true);
      }
    });
  }

  function openStream() {
    if (state.demo) {
      toast('Demo mode: there is no stream to open.', 'warn');
      return;
    }
    if (!state.base) {
      toast('Connect a codespace first.', 'warn');
      return;
    }
    window.open(`${state.base}/`, '_blank', 'noopener,noreferrer');
  }

  function applyAppearance() {
    el.html.dataset.theme = state.prefs.theme;
    el.html.classList.toggle('no-motion', !state.prefs.motion);
  }

  function boot() {
    loadState();
    applyAppearance();
    bind();

    const params = new URLSearchParams(location.search);
    if (params.get('theme') === 'light' || params.get('theme') === 'dark') {
      state.prefs.theme = params.get('theme');
      applyAppearance();
    }
    el.codespaceInput.value = state.url;
    el.logAuto.checked = state.prefs.logAuto;
    el.logSelect.value = state.logName;

    // Served by the codespace at /console/: same origin as /glide/ and the stream,
    // so a private port works without CORS or GitHub cookie problems.
    const sameOrigin = /^\/console(\/|$)/.test(location.pathname);
    if (sameOrigin) {
      state.base = location.origin;
      state.url = location.origin;
      state.connected = true;
      el.codespaceInput.value = location.origin;
      route('session', { push: false });
      renderAll();
      startPolling();
      pollOnce();
      loadConfig(true);
      renderLogs(true);
      startLogTimer();
      return;
    }

    const keyMatch = (location.hash || '').match(/[#&]key=([^&]+)/);
    if (keyMatch) {
      try {
        state.key = decodeURIComponent(keyMatch[1]);
      } catch (_) {
        state.key = keyMatch[1];
      }
      saveState();
    }

    const hashView = (location.hash || '').replace(/^#\/?/, '').split('&')[0];
    if (params.has('demo')) {
      startDemo(String(params.get('demo') || '').includes('running'));
      renderStorageNote();
      return;
    }

    const deepLink = params.get('connect');
    if (deepLink) el.codespaceInput.value = deepLink;

    if (VIEWS.includes(hashView)) route(hashView, { push: false });
    else route(state.url && state.prefs.autoConnect ? 'session' : 'connect', { push: false });

    renderSettings();
    renderAll();
    renderInstallations();

    const autoTarget = deepLink || (state.prefs.autoConnect ? state.url : '');
    if (autoTarget) {
      el.codespaceInput.value = autoTarget;
      connect(autoTarget, { silent: true, autoOpen: true }).then((ok) => {
        if (!ok) {
          route('connect');
        } else if (VIEWS.includes(hashView) && hashView !== 'connect' && hashView !== 'session') {
          // keep deep links such as ?connect=…#/installations
          route(hashView, { push: false });
        }
      });
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
