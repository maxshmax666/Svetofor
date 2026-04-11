(function initPermissionUiState(globalScope) {
  const GEO_BLOCKING_STATES = new Set(["denied", "error", "unavailable", "disabled"]);

  function computeBlockingIssues(permissionMatrix, options) {
    const matrix = permissionMatrix || {};
    const hasGeolocationApi = options?.hasGeolocationApi !== false;
    const geoState = String(matrix.geo || "unknown");
    const blockingIssues = [];

    if (!hasGeolocationApi || GEO_BLOCKING_STATES.has(geoState)) {
      blockingIssues.push({
        code: "geo_blocked",
        state: hasGeolocationApi ? geoState : "unavailable",
        message: "Нужно включить геолокацию",
      });
    }

    return blockingIssues;
  }

  function mapPermissionStateToUiState(permissionMatrix, options) {
    const blockingIssues = computeBlockingIssues(permissionMatrix, options);
    if (blockingIssues.length === 0) {
      return {
        statusText: "Готов к работе",
        statusTone: "ok",
        blockingIssues,
        cta: null,
      };
    }

    return {
      statusText: "Нужно включить геолокацию",
      statusTone: "bad",
      blockingIssues,
      cta: {
        action: "open_settings",
        label: "Открыть настройки",
      },
    };
  }

  function detectPlatform(userAgent) {
    const ua = String(userAgent || "").toLowerCase();
    if (/android/.test(ua)) return "android";
    if (/iphone|ipad|ipod/.test(ua)) return "ios";
    return "other";
  }

  function getSettingsDeepLinks(platform) {
    if (platform === "ios") {
      return ["App-Prefs:root=Privacy&path=LOCATION", "app-settings:"];
    }
    if (platform === "android") {
      return [
        "intent:#Intent;action=android.settings.LOCATION_SOURCE_SETTINGS;end",
        "android-app://com.android.settings"
      ];
    }
    return [];
  }

  function openSettingsDeepLink(options) {
    const userAgent = options?.userAgent || "";
    const platform = options?.platform || detectPlatform(userAgent);
    const openWindow = options?.openWindow || ((url) => globalScope.open(url, "_blank"));
    const onFallback = typeof options?.onFallback === "function" ? options.onFallback : () => {};
    const links = getSettingsDeepLinks(platform);

    if (!links.length) {
      onFallback();
      return false;
    }

    for (const url of links) {
      try {
        const result = openWindow(url);
        if (result !== null) {
          return true;
        }
      } catch (_) {
        // noop
      }
    }

    onFallback();
    return false;
  }

  const api = {
    computeBlockingIssues,
    mapPermissionStateToUiState,
    detectPlatform,
    getSettingsDeepLinks,
    openSettingsDeepLink,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
  globalScope.permissionUiState = api;
})(typeof window !== "undefined" ? window : globalThis);
