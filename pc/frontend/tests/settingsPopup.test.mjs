import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {fileURLToPath} from 'node:url'
import {dirname,resolve} from 'node:path'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const page = readFileSync(resolve(root, 'integration.html'), 'utf8')
const main = readFileSync(resolve(root, 'src/main.js'), 'utf8')
const popup = readFileSync(resolve(root, 'src/adminController.js'), 'utf8')
const launcher = readFileSync(resolve(root, 'src/launcherControl.js'), 'utf8')

test('settings are in a standalone popup, not overlaying the main viewer', () => {
  assert.match(main, /window\.open\('\/integration\.html'/)
  assert.doesNotMatch(main, /<aside class="viewer-settings-panel"/)
  assert.match(page, /id="admin-source"/)
})
test('all independent settings controls are in popup', () => {
  const ids = [
    'admin-location-mode', 'admin-source', 'admin-live-action-mode',
    'admin-manual-points', 'admin-preset', 'admin-arms', 'admin-legs',
    'admin-camera', 'admin-mirror', 'admin-all-live', 'admin-reset'
  ]
  for (const id of ids) assert.ok(page.includes(`id="${id}"`), id)
})
test('main and popup exchange settings on same BroadcastChannel', () => {
  const channel = 'wisensing-viewer-settings-v1'
  assert.ok(main.includes(channel))
  assert.ok(popup.includes(channel))
  assert.match(main, /type === 'hello'/)
  assert.match(popup, /type:'hello'/)
})
test('standalone browser mode cannot kill unmanaged servers', () => {
  assert.match(launcher, /#wise-launcher=/)
  assert.match(launcher, /X-WiSensing-Token/)
  assert.match(main, /setupManagedShutdown\(\)/)
})
