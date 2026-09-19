// ==UserScript==
// @name         ompweb — Silero-озвучивание ответов
// @namespace    local.ompweb
// @version      2.0.0
// @description  Локальное озвучивание ответов через Silero TTS с выбором голоса и скорости.
// @match        http://localhost:30177/*
// @match        http://127.0.0.1:30177/*
// @match        http://0.0.0.0:30177/*
// @grant        GM_xmlhttpRequest
// @connect      127.0.0.1
// @connect      localhost
// @run-at       document-idle
// ==/UserScript==

(() => {
  "use strict";

  const TTS_URL = "http://127.0.0.1:30179/synthesize";
  const AUTO_KEY = "ompweb-speech-auto";
  const VOICE_KEY = "ompweb-silero-voice";
  const RATE_KEY = "ompweb-silero-rate";
  const CARD_SELECTOR = ".chat-message";
  const ACTIONS_SELECTOR = ".message-copy-actions";
  const TEXT_SELECTOR = "[data-message-text], .markdown-body";
  const CONTROLS_CLASS = "ompweb-speech-controls";
  const PROCESSED_ATTR = "data-ompweb-speech-ready";
  const SEEN_ATTR = "data-ompweb-speech-seen";
  const MAX_CHARS_PER_CHUNK = 900;
  const VOICES = [
    ["xenia", "Ксения"],
    ["eugene", "Евгений"],
    ["aidar", "Айдар"],
    ["baya", "Байя"],
    ["kseniya", "Ксения 2"],
  ];
  const RATES = [0.8, 1, 1.2, 1.35, 1.5];

  let currentCard = null;
  let currentAudio = null;
  let currentAudioUrl = null;
  let currentRequest = null;
  let speakingGeneration = 0;
  let initialized = false;
  let lastError = "";

  const style = document.createElement("style");
  style.textContent = `
    .${CONTROLS_CLASS} { display: inline-flex; align-items: center; gap: 3px; margin-top: 6px; }
    .${CONTROLS_CLASS} button, .ompweb-speech-floating, .ompweb-speech-panel button,
    .ompweb-speech-panel select {
      min-height: 26px; padding: 3px 8px;
      border: 1px solid var(--border); border-radius: var(--radius-control, 6px);
      background: var(--bg-panel); color: var(--text-muted);
      font: inherit; font-size: 11px;
    }
    .${CONTROLS_CLASS} button, .ompweb-speech-floating, .ompweb-speech-panel button { cursor: pointer; }
    .${CONTROLS_CLASS} button:hover, .ompweb-speech-floating:hover, .ompweb-speech-panel button:hover {
      color: var(--text); border-color: var(--text-dim);
    }
    .${CONTROLS_CLASS} button:disabled { cursor: default; opacity: .45; }
    .ompweb-speech-floating {
      position: fixed; right: 14px; z-index: 1000;
      display: inline-flex; align-items: center; gap: 5px;
      box-shadow: 0 4px 14px rgb(0 0 0 / 18%);
    }
    .ompweb-speech-auto { bottom: 86px; }
    .ompweb-speech-settings-button { bottom: 122px; }
    .ompweb-speech-auto[aria-pressed="true"] { color: var(--status-success, #45a66b); }
    .ompweb-speech-panel {
      position: fixed; right: 14px; bottom: 158px; z-index: 1001;
      display: none; width: 230px; padding: 10px;
      border: 1px solid var(--border); border-radius: var(--radius-card, 8px);
      background: var(--bg-panel); color: var(--text);
      box-shadow: 0 8px 24px rgb(0 0 0 / 24%);
    }
    .ompweb-speech-panel[data-open="true"] { display: grid; gap: 8px; }
    .ompweb-speech-panel label { display: grid; gap: 4px; font-size: 11px; color: var(--text-muted); }
    .ompweb-speech-error { font-size: 10px; line-height: 1.35; color: var(--status-error, #d45b5b); }
  `;
  document.head.appendChild(style);

  function autoEnabled() {
    return localStorage.getItem(AUTO_KEY) === "1";
  }

  function selectedVoice() {
    const stored = localStorage.getItem(VOICE_KEY);
    return VOICES.some(([id]) => id === stored) ? stored : "xenia";
  }

  function selectedRate() {
    const stored = Number(localStorage.getItem(RATE_KEY));
    return RATES.includes(stored) ? stored : 1.2;
  }

  function voiceLabel() {
    return VOICES.find(([id]) => id === selectedVoice())?.[1] || selectedVoice();
  }

  function updateFloatingButtons() {
    const auto = document.querySelector(".ompweb-speech-auto");
    if (auto) {
      const enabled = autoEnabled();
      const label = enabled ? "Автоозвучивание: вкл" : "Автоозвучивание: выкл";
      if (auto.getAttribute("aria-pressed") !== String(enabled)) auto.setAttribute("aria-pressed", String(enabled));
      if (auto.textContent !== label) auto.textContent = label;
    }
    const settings = document.querySelector(".ompweb-speech-settings-button");
    const settingsLabel = `${voiceLabel()} · ${selectedRate()}×`;
    if (settings && settings.textContent !== settingsLabel) settings.textContent = settingsLabel;
  }

  function ensureFloatingControls() {
    if (!document.querySelector(".ompweb-speech-auto")) {
      const auto = document.createElement("button");
      auto.type = "button";
      auto.className = "ompweb-speech-floating ompweb-speech-auto";
      auto.title = "Автоматически читать новые завершённые ответы";
      auto.addEventListener("click", () => {
        localStorage.setItem(AUTO_KEY, autoEnabled() ? "0" : "1");
        updateFloatingButtons();
      });
      document.body.appendChild(auto);
    }

    if (!document.querySelector(".ompweb-speech-settings-button")) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "ompweb-speech-floating ompweb-speech-settings-button";
      button.title = "Настройки Silero TTS";
      button.addEventListener("click", () => {
        const panel = document.querySelector(".ompweb-speech-panel");
        panel.dataset.open = panel.dataset.open === "true" ? "false" : "true";
      });
      document.body.appendChild(button);
    }

    if (!document.querySelector(".ompweb-speech-panel")) {
      const panel = document.createElement("div");
      panel.className = "ompweb-speech-panel";
      panel.dataset.open = "false";

      const voiceLabelElement = document.createElement("label");
      voiceLabelElement.textContent = "Голос";
      const voice = document.createElement("select");
      for (const [id, label] of VOICES) voice.add(new Option(label, id, false, id === selectedVoice()));
      voice.addEventListener("change", () => {
        localStorage.setItem(VOICE_KEY, voice.value);
        updateFloatingButtons();
      });
      voiceLabelElement.appendChild(voice);

      const rateLabelElement = document.createElement("label");
      rateLabelElement.textContent = "Скорость";
      const rate = document.createElement("select");
      for (const value of RATES) rate.add(new Option(`${value}×`, String(value), false, value === selectedRate()));
      rate.addEventListener("change", () => {
        localStorage.setItem(RATE_KEY, rate.value);
        updateFloatingButtons();
      });
      rateLabelElement.appendChild(rate);

      const test = document.createElement("button");
      test.type = "button";
      test.textContent = "Проверить голос";
      test.addEventListener("click", () => speakText("Проверка локального голоса Silero. Скорость можно изменить в настройках."));

      const error = document.createElement("div");
      error.className = "ompweb-speech-error";
      panel.append(voiceLabelElement, rateLabelElement, test, error);
      document.body.appendChild(panel);
    }

    updateFloatingButtons();
  }

  function readableText(card) {
    const clones = [...card.querySelectorAll(TEXT_SELECTOR)].map((body) => {
      const clone = body.cloneNode(true);
      clone.querySelectorAll("pre, code, .markdown-code-header, .katex-mathml, svg, button, [aria-hidden='true']")
        .forEach((node) => node.remove());
      clone.querySelectorAll("a").forEach((link) => {
        const label = link.textContent?.trim();
        link.replaceWith(document.createTextNode(label && !/^https?:\/\//i.test(label) ? label : ""));
      });
      clone.querySelectorAll("img").forEach((image) => image.replaceWith(document.createTextNode(image.alt || "")));
      return clone.textContent || "";
    });

    return clones
      .join("\n\n")
      .replace(/https?:\/\/\S+/gi, " ")
      .replace(/[`*_#>|~]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function splitText(text) {
    if (text.length <= MAX_CHARS_PER_CHUNK) return [text];
    const sentences = text.match(/[^.!?…]+[.!?…]+|[^.!?…]+$/g) || [text];
    const chunks = [];
    let chunk = "";
    for (const sentence of sentences) {
      if (chunk && chunk.length + sentence.length > MAX_CHARS_PER_CHUNK) {
        chunks.push(chunk.trim());
        chunk = "";
      }
      chunk += sentence;
    }
    if (chunk.trim()) chunks.push(chunk.trim());
    return chunks;
  }

  function updateCardButtons() {
    document.querySelectorAll(`.${CONTROLS_CLASS}`).forEach((controls) => {
      const card = controls.closest(CARD_SELECTOR);
      const isCurrent = card === currentCard;
      const speak = controls.querySelector("[data-action='speak']");
      const stop = controls.querySelector("[data-action='stop']");
      if (speak) {
        if (speak.disabled !== isCurrent) speak.disabled = isCurrent;
        const label = isCurrent ? "Готовлю/читаю…" : "Озвучить";
        if (speak.textContent !== label) speak.textContent = label;
      }
      if (stop && stop.disabled === isCurrent) stop.disabled = !isCurrent;
    });
    const error = document.querySelector(".ompweb-speech-error");
    if (error && error.textContent !== lastError) error.textContent = lastError;
  }

  function releaseAudio() {
    if (currentAudio) {
      currentAudio.pause();
      currentAudio.src = "";
      currentAudio = null;
    }
    if (currentAudioUrl) {
      URL.revokeObjectURL(currentAudioUrl);
      currentAudioUrl = null;
    }
  }

  function requestAudio(text) {
    return new Promise((resolve, reject) => {
      currentRequest = GM_xmlhttpRequest({
        method: "POST",
        url: TTS_URL,
        headers: { "Content-Type": "application/json" },
        data: JSON.stringify({ text, speaker: selectedVoice() }),
        responseType: "arraybuffer",
        overrideMimeType: "application/octet-stream",
        timeout: 60000,
        onload: (response) => {
          if (response.status >= 200 && response.status < 300) {
            resolve(new Blob([response.response], { type: "audio/wav" }));
          } else {
            reject(new Error(`Silero вернул HTTP ${response.status}`));
          }
        },
        onerror: () => reject(new Error("Браузер не подключился к локальному Silero")),
        ontimeout: () => reject(new Error("Silero не ответил за 60 секунд")),
        onabort: () => reject(new DOMException("Запрос отменён", "AbortError")),
      });
    });
  }

  function stopSpeaking() {
    speakingGeneration += 1;
    currentRequest?.abort();
    currentRequest = null;
    releaseAudio();
    currentCard = null;
    updateCardButtons();
  }

  async function speakText(text, card = null) {
    if (!text) return;
    stopSpeaking();
    currentCard = card;
    lastError = "";
    const generation = ++speakingGeneration;
    const chunks = splitText(text);
    updateCardButtons();

    try {
      for (const chunk of chunks) {
        if (generation !== speakingGeneration) return;
        const blob = await requestAudio(chunk);
        if (generation !== speakingGeneration) return;
        currentAudioUrl = URL.createObjectURL(blob);
        currentAudio = new Audio(currentAudioUrl);
        currentAudio.playbackRate = selectedRate();
        await new Promise((resolve, reject) => {
          currentAudio.onended = resolve;
          currentAudio.onerror = () => reject(new Error("Браузер не смог воспроизвести WAV"));
          currentAudio.play().catch(reject);
        });
        releaseAudio();
      }
    } catch (error) {
      if (error.name !== "AbortError") {
        lastError = `${error.message}. Запустите .omp/start-silero-tts.sh`;
        console.error("[ompweb-speech]", error);
      }
    } finally {
      if (generation === speakingGeneration) {
        currentRequest = null;
        releaseAudio();
        currentCard = null;
        updateCardButtons();
      }
    }
  }

  function speakCard(card) {
    return speakText(readableText(card), card);
  }

  function addControls(card, actions) {
    if (card.hasAttribute(PROCESSED_ATTR)) return;
    card.setAttribute(PROCESSED_ATTR, "1");

    const controls = document.createElement("span");
    controls.className = CONTROLS_CLASS;

    const speak = document.createElement("button");
    speak.type = "button";
    speak.dataset.action = "speak";
    speak.textContent = "Озвучить";
    speak.addEventListener("click", () => speakCard(card));

    const stop = document.createElement("button");
    stop.type = "button";
    stop.dataset.action = "stop";
    stop.textContent = "Стоп";
    stop.disabled = true;
    stop.addEventListener("click", stopSpeaking);

    controls.append(speak, stop);
    if (actions) actions.insertAdjacentElement("afterend", controls);
    else card.appendChild(controls);
  }

  function scan() {
    ensureFloatingControls();
    const completed = [];

    document.querySelectorAll(CARD_SELECTOR).forEach((card) => {
      if (!card.querySelector(TEXT_SELECTOR)) return;
      addControls(card, card.querySelector(ACTIONS_SELECTOR));
      if (!card.hasAttribute(SEEN_ATTR)) {
        card.setAttribute(SEEN_ATTR, "1");
        completed.push(card);
      }
    });

    if (initialized && autoEnabled() && completed.length > 0) speakCard(completed.at(-1));
    initialized = true;
    updateCardButtons();
  }

  const observer = new MutationObserver(() => queueMicrotask(scan));
  observer.observe(document.body, { childList: true, subtree: true });
  window.addEventListener("beforeunload", stopSpeaking);
  scan();
})();
