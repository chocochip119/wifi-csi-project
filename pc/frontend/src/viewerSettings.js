// UI의 테스트 입력만 선택합니다. Backend/FPGA 결과와 모델 분류값은 변경하지 않습니다.
export const DEFAULT_VIEWER_SETTINGS = Object.freeze({
  locationMode: 'live',
  manualPoint: 'p05',
  jointsMode: 'live',
  jointsSample: 'stand',
  motionMode: 'live',
  motionSample: 'stand',
  liveArms: true,
  liveLegs: true
})

export function resolveViewerLocation(snapshot, settings) {
  const manual = settings.locationMode === 'manual'
  const location = snapshot?.location ?? {}
  const pointId = manual ? settings.manualPoint : String(location.point_id ?? '').toLowerCase()
  const valid = manual || location.valid === true
  if (!valid) return {valid: false, pointId: null, zone: null, posture: 'unknown', empty: false, manual}
  if (!manual && (snapshot?.person?.presence === false || pointId === 'empty')) {
    return {valid: true, pointId: 'empty', zone: null, posture: 'empty', empty: true, manual}
  }
  if (pointId === 'p10') return {valid: true, pointId, zone: 5, posture: 'sitting', empty: false, manual}
  const match = /^p0?([1-9])$/.exec(pointId)
  const zone = match ? Number(match[1]) : (!manual ? Number(location.zone) : NaN)
  if (!Number.isInteger(zone) || zone < 1 || zone > 9) {
    return {valid: false, pointId: null, zone: null, posture: 'unknown', empty: false, manual}
  }
  return {valid: true, pointId: `p${String(zone).padStart(2, '0')}`, zone, posture: manual ? 'standing' : 'standing', empty: false, manual}
}

export function selectViewerPose(mode, livePose, sampleName, createSample) {
  if (mode === 'off') return null
  if (mode === 'sample') return createSample(sampleName)
  return livePose?.valid ? livePose : null
}
