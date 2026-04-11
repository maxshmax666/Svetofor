const test = require('node:test');
const assert = require('node:assert/strict');

const {
  mapPermissionStateToUiState,
  computeBlockingIssues,
} = require('../web/permission_ui_state');

test('permission-state -> ui-state: all-ok', () => {
  const uiState = mapPermissionStateToUiState({
    geo: 'granted',
    camera: 'granted',
    microphone: 'granted',
    notifications: 'granted',
  }, { hasGeolocationApi: true });

  assert.equal(uiState.statusText, 'Готов к работе');
  assert.equal(uiState.statusTone, 'ok');
  assert.equal(uiState.blockingIssues.length, 0);
  assert.equal(uiState.cta, null);
});

test('permission-state -> ui-state: geo-denied', () => {
  const uiState = mapPermissionStateToUiState({
    geo: 'denied',
    camera: 'granted',
    microphone: 'granted',
    notifications: 'granted',
  }, { hasGeolocationApi: true });

  assert.equal(uiState.statusText, 'Нужно включить геолокацию');
  assert.equal(uiState.statusTone, 'bad');
  assert.equal(uiState.blockingIssues.length, 1);
  assert.equal(uiState.blockingIssues[0].code, 'geo_blocked');
  assert.equal(uiState.cta?.action, 'open_settings');
});

test('permission-state -> ui-state: unknown is not blocking', () => {
  const blockingIssues = computeBlockingIssues({ geo: 'unknown' }, { hasGeolocationApi: true });
  const uiState = mapPermissionStateToUiState({ geo: 'unknown' }, { hasGeolocationApi: true });

  assert.equal(blockingIssues.length, 0);
  assert.equal(uiState.statusText, 'Готов к работе');
  assert.equal(uiState.statusTone, 'ok');
  assert.equal(uiState.blockingIssues.length, 0);
});
