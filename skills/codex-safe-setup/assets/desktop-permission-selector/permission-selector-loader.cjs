'use strict';

if (process.type === 'browser') {
  const crypto = require('node:crypto');
  const fs = require('node:fs');
  const Module = require('node:module');
  const path = require('node:path');

  const selectorGate = '4226282475';
  const statusChannel = 'codex-safe-setup:desktop-selector-status';
  const statusPath = process.env.CSS_DESKTOP_SELECTOR_STATUS_PATH;
  const installationId = process.env.CSS_DESKTOP_SELECTOR_INSTALLATION_ID ?? null;
  const preloadPath = process.env.CSS_DESKTOP_SELECTOR_PRELOAD;
  const expectedPreloadHash = process.env.CSS_DESKTOP_SELECTOR_PRELOAD_SHA256;
  const probeMode = process.env.CSS_DESKTOP_SELECTOR_PROBE_MODE;

  const writeStatus = (status, evidence = {}) => {
    if (!statusPath) return;
    const record = {
      status,
      timestampUtc: new Date().toISOString(),
      processId: process.pid,
      selectorGate,
      installationId,
      ...evidence,
    };
    try {
      fs.mkdirSync(path.dirname(statusPath), { recursive: true });
      fs.writeFileSync(statusPath, JSON.stringify(record, null, 2), 'utf8');
    } catch {
      // Status is diagnostic only. Validation below still fails closed.
    }
  };

  const refuse = (message) => {
    writeStatus('LOADER_REFUSED', { message });
    throw new Error(`Codex Safe Setup Desktop loader refused: ${message}`);
  };

  if (!preloadPath || !path.isAbsolute(preloadPath)) {
    refuse('The preload path is missing or not absolute.');
  }
  if (!expectedPreloadHash || !/^[a-f0-9]{64}$/i.test(expectedPreloadHash)) {
    refuse('The expected preload SHA-256 is missing or invalid.');
  }
  if (!fs.existsSync(preloadPath) || !fs.statSync(preloadPath).isFile()) {
    refuse('The recorded preload file is missing.');
  }
  const actualPreloadHash = crypto
    .createHash('sha256')
    .update(fs.readFileSync(preloadPath))
    .digest('hex');
  if (actualPreloadHash.toLowerCase() !== expectedPreloadHash.toLowerCase()) {
    refuse('The preload file does not match its recorded SHA-256.');
  }

  let electronInstalled = false;
  let preloadReported = false;
  const originalLoad = Module._load;

  const installElectronHook = (electron) => {
    if (electronInstalled) return;
    electronInstalled = true;
    Module._load = originalLoad;

    if (!electron?.app || !electron?.session || !electron?.ipcMain) {
      refuse('The Electron main-process API is unavailable.');
    }
    if (probeMode === 'electron-hook') {
      writeStatus('PROBE_PASS', {
        electronAppAvailable: true,
        preloadSha256: actualPreloadHash,
      });
      process.nextTick(() => process.exit(0));
      return;
    }

    electron.ipcMain.on(statusChannel, (event, payload) => {
      const matches =
        payload?.installed === true && payload?.selectorGate === selectorGate;
      let sourceScheme = null;
      try {
        sourceScheme = new URL(event.sender.getURL()).protocol;
      } catch {
        sourceScheme = null;
      }
      if (matches) preloadReported = true;
      writeStatus(matches ? 'PRELOAD_ACTIVE' : 'PRELOAD_REFUSED', {
        preloadSha256: actualPreloadHash,
        sourceScheme,
        message: typeof payload?.message === 'string' ? payload.message.slice(0, 240) : null,
      });
    });

    const configureSessionPreload = () => {
      try {
        const current = electron.session.defaultSession.getPreloads();
        const normalizedTarget = path.resolve(preloadPath).toLowerCase();
        const next = current.some(
          (entry) => path.resolve(entry).toLowerCase() === normalizedTarget,
        )
          ? current
          : [...current, preloadPath];
        electron.session.defaultSession.setPreloads(next);
        const installed = electron.session.defaultSession
          .getPreloads()
          .some((entry) => path.resolve(entry).toLowerCase() === normalizedTarget);
        if (!installed) refuse('Electron did not retain the session preload.');
        writeStatus('LOADER_ACTIVE', {
          preloadSha256: actualPreloadHash,
          preservedSessionPreloads: current.length,
        });
        setTimeout(() => {
          if (!preloadReported) {
            writeStatus('PRELOAD_PENDING', {
              preloadSha256: actualPreloadHash,
              message: 'No renderer has reported preload activation yet.',
            });
          }
        }, 15000).unref();
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        writeStatus('LOADER_REFUSED', { message });
        electron.app.exit(94);
      }
    };

    if (electron.app.isReady()) configureSessionPreload();
    else electron.app.once('ready', configureSessionPreload);
  };

  Module._load = function cssDesktopSelectorModuleLoad(request, parent, isMain) {
    const loaded = originalLoad.call(this, request, parent, isMain);
    if (request === 'electron') installElectronHook(loaded);
    return loaded;
  };
}
