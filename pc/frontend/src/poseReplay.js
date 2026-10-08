import { JOINT_IDS, sanitizePose } from './poseInput.js'

const JOINT_NAMES = [
  'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
  'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
  'left_knee', 'right_knee', 'left_ankle', 'right_ankle'
]

function raw24ToPose(source) {
  const raw = source.int8
  const scale = Number(source.output_scale)
  if (!Array.isArray(raw) || raw.length !== 24 || !Number.isFinite(scale) || scale <= 0) return null
  if (!raw.every(n => Number.isInteger(n) && n >= -128 && n <= 127)) return null
  return {
    valid: true, coordinate_space: 'model_output',
    joints: JOINT_IDS.map((id, index) => ({
      id, name: JOINT_NAMES[index], x: raw[index * 2] * scale, y: raw[index * 2 + 1] * scale
    }))
  }
}

function poseOnlySnapshot(pose) {
  return {
    type: 'snapshot', version: 1,
    // 위치 좌표가 없는 Pose 전용 녹화는 임의 Zone을 '예측'하지 않는다.
    location: { valid: false, point_id: null, zone: null },
    person: { valid: false, presence: null, posture: 'unknown' },
    pose
  }
}

function asSnapshot(value) {
  if (!value || typeof value !== 'object') return null
  if (value.type === 'snapshot' && value.pose) {
    // 저장된 Backend snapshot은 empty/unavailable 프레임도 유지해야 재생 타임라인이 정확하다.
    // 유효하지 않은 관절은 3D/스켈레톤 입력에 전달하지 않는다.
    const pose = sanitizePose(value.pose)
    return { ...value, pose: pose || { ...value.pose, valid: false, joints: [] } }
  }
  const rawPose = value.type === 'pose24' || value.int8 ? raw24ToPose(value) : null
  const pose = sanitizePose(rawPose || (value.pose?.joints ? value.pose : value))
  return pose ? poseOnlySnapshot(pose) : null
}

export function parsePoseRecording(text) {
  if (typeof text !== 'string' || text.length > 10_000_000) throw new Error('파일이 비어 있거나 10MB 초과')
  let parsed
  try { parsed = JSON.parse(text.replace(/^\uFEFF/, '')) }
  catch {
    parsed = text.replace(/^\uFEFF/, '').split(/\r?\n/).map((line, index) => ({ line, index }))
      .filter(({ line }) => line.trim()).map(({ line, index }) => {
        try { return JSON.parse(line) }
        catch { throw new Error(`JSONL ${index + 1}행을 파싱할 수 없습니다.`) }
      })
  }
  const candidates = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.frames) ? parsed.frames : [parsed]
  if (candidates.length > 6000) throw new Error('최대 6000 프레임까지 재생 가능')
  const frames = candidates.map(asSnapshot).filter(Boolean)
  if (!frames.some(frame => sanitizePose(frame.pose))) {
    throw new Error('실제 재생 가능한 12관절 프레임이 없습니다. pose.valid=true, 12개 좌표 및 scale을 확인하세요.')
  }
  return frames
}
