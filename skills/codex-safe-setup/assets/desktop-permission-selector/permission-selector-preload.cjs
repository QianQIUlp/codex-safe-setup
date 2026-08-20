'use strict';

const { contextBridge, ipcRenderer } = require('electron');

const selectorGate = '4226282475';
const statusChannel = 'codex-safe-setup:desktop-selector-status';

try {
  if (typeof contextBridge.executeInMainWorld !== 'function') {
    throw new Error('contextBridge.executeInMainWorld is unavailable.');
  }

  const result = contextBridge.executeInMainWorld({
    func: (gateName) => {
      const existing = globalThis.__STATSIG__;
      if (existing?.__permissionSelectorOverrideInstalled) {
        return { installed: true, alreadyInstalled: true };
      }

      const statsigGlobal = existing ?? {};
      const originalInstances = statsigGlobal.instances ?? {};
      const installOverride = (client) => {
        if (!client || client.__permissionSelectorOverrideInstalled) return client;
        const previous = client.overrideAdapter;
        client.overrideAdapter = {
          ...previous,
          getGateOverride(gate, user, options) {
            if (gate?.name === gateName) {
              return {
                ...gate,
                value: true,
                details: { ...gate.details, reason: 'LocalOverride' },
              };
            }
            return typeof previous?.getGateOverride === 'function'
              ? previous.getGateOverride.call(previous, gate, user, options)
              : gate;
          },
        };
        Object.defineProperty(client, '__permissionSelectorOverrideInstalled', {
          value: true,
        });
        return client;
      };

      const instances = new Proxy(originalInstances, {
        set(target, property, value) {
          return Reflect.set(target, property, installOverride(value));
        },
      });
      for (const client of Object.values(originalInstances)) installOverride(client);

      let firstInstance = installOverride(statsigGlobal.firstInstance ?? null);
      Object.defineProperties(statsigGlobal, {
        instances: {
          configurable: true,
          enumerable: true,
          get: () => instances,
          set: (value) => {
            for (const client of Object.values(value ?? {})) installOverride(client);
          },
        },
        firstInstance: {
          configurable: true,
          enumerable: true,
          get: () => firstInstance,
          set: (value) => {
            firstInstance = installOverride(value);
          },
        },
        __permissionSelectorOverrideInstalled: { value: true },
      });
      globalThis.__STATSIG__ = statsigGlobal;
      return { installed: true, alreadyInstalled: false };
    },
    args: [selectorGate],
  });

  ipcRenderer.send(statusChannel, {
    installed: result?.installed === true,
    selectorGate,
    message: result?.alreadyInstalled ? 'Override was already active.' : 'Override installed.',
  });
} catch (error) {
  ipcRenderer.send(statusChannel, {
    installed: false,
    selectorGate,
    message: error instanceof Error ? error.message : String(error),
  });
}
