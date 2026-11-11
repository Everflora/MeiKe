{{flutter_js}}
{{flutter_build_config}}

window.addEventListener('flutter-first-frame', () => {
  document.getElementById('loading')?.remove();
}, {once: true});

_flutter.loader.load({
  config: {renderer: 'canvaskit', canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href},
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
    } catch (error) {
      window.meikeStartupFailed?.();
      console.error('MeiKe initialization failed', error);
    }
  }
}).catch(() => window.meikeStartupFailed?.());
