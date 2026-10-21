{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {renderer: 'canvaskit', canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href},
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
      document.getElementById('loading')?.remove();
    } catch (error) {
      window.meikeStartupFailed?.();
      console.error('MeiKe initialization failed', error);
    }
  }
}).catch(() => window.meikeStartupFailed?.());
