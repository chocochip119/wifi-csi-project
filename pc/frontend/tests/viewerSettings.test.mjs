import test from 'node:test'
import assert from 'node:assert/strict'
import {DEFAULT_VIEWER_SETTINGS, resolveViewerLocation, selectViewerPose} from '../src/viewerSettings.js'

const sample = (point, valid = true, presence = true) => ({
  location: {valid, point_id: point}, person: {presence, posture:'standing'}
})
test('P05 stands in Zone 5 and P10 sits in the SAME Zone 5', () => {
  const p05 = resolveViewerLocation(sample('p05'), DEFAULT_VIEWER_SETTINGS)
  const p10 = resolveViewerLocation(sample('p10'), DEFAULT_VIEWER_SETTINGS)
  assert.equal(p05.zone, 5)
  assert.equal(p10.zone, 5)
  assert.equal(p05.posture, 'standing')
  assert.equal(p10.posture, 'sitting')
})
test('manual P10 ignores unstable incoming location but not other signals', () => {
  const incoming = sample('p03')
  const position = resolveViewerLocation(incoming, {...DEFAULT_VIEWER_SETTINGS,locationMode:'manual',manualPoint:'p10'})
  assert.equal(position.zone,5)
  assert.equal(position.posture,'sitting')
  assert.equal(incoming.location.point_id,'p03')
})
test('every manual zone is supported', () => {
  for(let i=1;i<=9;i++) {
    const setting = {...DEFAULT_VIEWER_SETTINGS,locationMode:'manual',manualPoint:'p'+String(i).padStart(2,'0')}
    const position=resolveViewerLocation(sample('empty',false,false),setting)
    assert.equal(position.zone,i)
    assert.equal(position.empty,false)
    assert.equal(position.posture,'standing')
  }
})
test('LIVE empty and invalid position are not converted to test positions', () => {
  assert.equal(resolveViewerLocation(sample('empty',true,false), DEFAULT_VIEWER_SETTINGS).empty,true)
  assert.equal(resolveViewerLocation(sample('p04',false), DEFAULT_VIEWER_SETTINGS).valid,false)
})
test('center display mode keeps actual location result independent of 3D position', () => {
  const incoming = sample('p03')
  const location = resolveViewerLocation(incoming, {...DEFAULT_VIEWER_SETTINGS, locationMode:'center'})
  assert.equal(location.valid,true)
  assert.equal(location.zone,3)
  assert.equal(location.pointId,'p03')
  assert.equal(incoming.location.point_id,'p03')
})
test('2D joint sources can be independently LIVE, TEST, or OFF', () => {
  const live={valid:true,joints:[{id:11,x:0.1,y:0.2}]}
  const gen=(name)=>({valid:true,test_pose:name})
  assert.strictEqual(selectViewerPose('live',live,'stand',gen), live)
  assert.equal(selectViewerPose('sample',live,'squat',gen).test_pose,'squat')
  assert.strictEqual(selectViewerPose('off',live,'stand',gen),null)
  assert.strictEqual(selectViewerPose('live',{valid:false},'stand',gen),null)
})

test('live arm and leg tracking are enabled by default for live pose validation', () => {
  assert.equal(DEFAULT_VIEWER_SETTINGS.liveArms, true)
  assert.equal(DEFAULT_VIEWER_SETTINGS.liveLegs, true)
})

test('a single selected 12-joint input can be shared by skeleton and rig', () => {
  const live={valid:true,coordinate_space:'model_output',joints:[{id:11,x:0.4,y:0.2}]}
  const samplePose={valid:true,coordinate_space:'fake_normalized',joints:[{id:11,x:0.3,y:0.15}]}
  const select = () => selectViewerPose('live',live,'stand',()=>samplePose)
  assert.strictEqual(select(),live)
  assert.equal(DEFAULT_VIEWER_SETTINGS.jointsMode,'live')
})
