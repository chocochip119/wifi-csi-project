import * as THREE from 'three'

// v9: T + K ON 상태에서만 실행되는 시각화용 2D->3D 다리 보정.
// 서기/걷기는 원본 Idle_Neutral / Walk가 전담하며, 매 프레임 mixer 이후에만 오버레이한다.
// 실제 CSI CNN의 2D 출력만으로 전후 깊이를 복원할 수 없으므로 스쿼트의 무릎 전방은 시연용 가정이다.
const vec = () => new THREE.Vector3()
const quat = () => new THREE.Quaternion()
const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
const smoothStep = (v) => v * v * (3 - 2 * v)
const norm = (name) => name.toLowerCase().replace(/[^a-z0-9]/g, '')
const FORWARD_LOCAL = new THREE.Vector3(0, 0, 1)

function findBone(root, wanted) {
  let found = null
  root.traverse((node) => {
    if (node.isBone && norm(node.name) === norm(wanted)) found = node
  })
  return found
}

// 인체의 대퇴골 / 경골 길이와 목표 발목 위치로 무릎의 3D 위치 계산.
// forward는 무릎이 구부러질 방향(+Z, 캐릭터 정면)을 나타낸다.
export function solveKnee(hip, ankle, upperLen, lowerLen, forward) {
  const delta = ankle.clone().sub(hip)
  const rawLength = delta.length()
  if (rawLength < 1e-6 || upperLen < 1e-6 || lowerLen < 1e-6) return null

  const reach = clamp(rawLength, Math.abs(upperLen - lowerLen) + 1e-4, upperLen + lowerLen - 1e-4)
  const along = (upperLen ** 2 - lowerLen ** 2 + reach ** 2) / (2 * reach)
  const perpendicular = Math.sqrt(Math.max(0, upperLen ** 2 - along ** 2))
  const axis = delta.normalize()
  const bend = forward.clone().addScaledVector(axis, -forward.dot(axis))
  if (bend.lengthSq() < 1e-8) bend.set(1, 0, 0).addScaledVector(axis, -axis.x)
  bend.normalize()
  return hip.clone().addScaledVector(axis, along).addScaledVector(bend, perpendicular)
}

function aimBone(node, localAxis, worldDirection, weight) {
  if (worldDirection.lengthSq() < 1e-8 || localAxis.lengthSq() < 1e-8 || weight <= 0) return
  const worldQuat = node.getWorldQuaternion(quat())
  const actual = localAxis.clone().applyQuaternion(worldQuat).normalize()
  const desired = worldDirection.clone().normalize()
  const delta = quat().setFromUnitVectors(actual, desired)
  const parentInv = node.parent.getWorldQuaternion(quat()).invert()
  const targetLocal = parentInv.multiply(delta).multiply(worldQuat).normalize()
  node.quaternion.slerp(targetLocal, clamp(weight, 0, 1))
  node.updateWorldMatrix(false, true)
}

// R 테스트에서는 2D 발목 높이 변화가 다리 들기 강도에만 관여한다.
// 깊이 방향은 2D 입력만으로 정해지지 않아 안전한 전방 회전을 가정한다.
function legLiftStrength(pose) {
  if (!pose?.valid || !Array.isArray(pose.joints)) return 0
  const pts = new Map(pose.joints.map((j) => [Number(j.id), j]))
  const hipL = pts.get(23), ankleL = pts.get(27)
  const hipR = pts.get(24), ankleR = pts.get(28)
  if (![hipL, ankleL, hipR, ankleR].every(Boolean)) return 0
  const leftSpan = Number(ankleL.y) - Number(hipL.y)
  const rightSpan = Number(ankleR.y) - Number(hipR.y)
  if (!Number.isFinite(leftSpan) || !Number.isFinite(rightSpan) || rightSpan < 0.1) return 0
  return clamp((rightSpan - leftSpan) / Math.max(rightSpan * 0.40, 1e-5), 0, 1)
}

// 뼈를 모델 정면 기준 X축 주위로 회전한다. 원래 Idle 포즈를 바탕으로 매 프레임 새로 계산한다.
function rotateWorldBone(bone, axisWorld, angle) {
  if (!bone || Math.abs(angle) < 1e-6) return
  const worldQ = bone.getWorldQuaternion(quat())
  const parentQ = bone.parent.getWorldQuaternion(quat())
  const rotation = quat().setFromAxisAngle(axisWorld, angle)
  bone.quaternion.copy(parentQ.invert().multiply(rotation.multiply(worldQ))).normalize()
  bone.updateWorldMatrix(false, true)
}

export class LegPreviewController {
  constructor(character) {
    this.character = character
    this.body = findBone(character, 'Body')
    this.hips = findBone(character, 'Hips')
    this.legs = ['L', 'R'].map((side) => ({
      side,
      upper: findBone(character, `UpperLeg.${side}`),
      lower: findBone(character, `LowerLeg.${side}`),
      foot: findBone(character, `Foot.${side}`),
      upperLength: 0,
      lowerLength: 0,
      shinAxis: null
    }))
    this.ready = !!this.body && !!this.hips && this.legs.every((leg) => leg.upper && leg.lower && leg.foot)
    // GLTF Idle_Neutral은 Hips 회전을 키프레임으로 복구하지 않으므로 별도로 기준값을 보관한다.
    this.baseHipsQuaternion = this.hips?.quaternion.clone() ?? null
    this.calibrated = false
    this.mode = null
    this.blend = 0
    this.lastFootHeight = null
    if (!this.ready) console.warn('[LegPreview v9] Required Body/Hips/leg/foot bones missing; preview disabled')
  }

  reset() {
    // 다음 프레임 AnimationMixer가 Body/Leg/Foot을 Idle_Neutral 값으로 복구한다.
    this.mode = null
    this.blend = 0
    this.lastFootHeight = null
    // 테스트 종료/서기로 전환할 때 상체 회전이 누적되지 않도록 반드시 복원.
    if (this.hips && this.baseHipsQuaternion) this.hips.quaternion.copy(this.baseHipsQuaternion)
  }

  calibrate() {
    if (!this.ready) return false
    this.character.updateMatrixWorld(true)
    for (const leg of this.legs) {
      const hip = leg.upper.getWorldPosition(vec())
      const knee = leg.lower.getWorldPosition(vec())
      const ankle = leg.foot.getWorldPosition(vec())
      leg.upperLength = hip.distanceTo(knee)
      leg.lowerLength = knee.distanceTo(ankle)
      leg.shinAxis = ankle.clone().sub(knee).normalize()
        .applyQuaternion(leg.lower.getWorldQuaternion(quat()).invert())
    }
    this.calibrated = this.legs.every((leg) => leg.upperLength > 0.05 && leg.lowerLength > 0.05)
    if (this.calibrated) console.log('[LegPreview v9] Calibrated. Squat: deeper hip drop, mild torso lean, planted feet')
    return this.calibrated
  }

  update(mode, delta, pose = null) {
    if (!this.ready || (mode !== 'squat' && mode !== 'legLift')) return
    if (!this.calibrated && !this.calibrate()) return
    if (this.mode !== mode) this.blend = 0
    this.mode = mode
    // 약 0.7초에 걸쳐 서서히 자세 진입. 기본 Idle 애니메이션의 본 값은 매 프레임 복구됨.
    this.blend = Math.min(1, this.blend + clamp(delta, 0, 0.05) * 1.45)
    const strength = smoothStep(this.blend)
    const facing = this.character.getWorldQuaternion(quat())
    const forward = FORWARD_LOCAL.clone().applyQuaternion(facing).normalize()

    // v9: R은 기존의 IK + 임의 발목 평행이동을 사용하지 않는다.
    // 이전 방식은 독립된 Foot Bone과 종아리의 목표점이 서로 충돌하여
    // SkinnedMesh가 위로 크게 늘어나는 문제가 있었다.
    if (mode === 'legLift') {
      const leg = this.legs.find((item) => item.side === 'L')
      const amount = legLiftStrength(pose) * strength
      if (!leg || amount <= 1e-5) {
        this.lastFootHeight = this.legs.map((item) => item.foot.getWorldPosition(vec()).y)
        return
      }
      this.character.updateMatrixWorld(true)
      const originalFootWorld = leg.foot.getWorldPosition(vec())
      const worldX = new THREE.Vector3(1, 0, 0).applyQuaternion(facing).normalize()

      // 골반부터 허벅지를 앞으로 들어 올리고 무릎을 구부린다.
      // 원본 애니메이션의 나머지 부분은 그대로 유지한다.
      const originalUpperQuaternion = leg.upper.quaternion.clone()
      const originalLowerQuaternion = leg.lower.quaternion.clone()
      rotateWorldBone(leg.upper, worldX, -0.85 * amount)
      this.character.updateMatrixWorld(true)
      rotateWorldBone(leg.lower, worldX, 1.25 * amount)
      this.character.updateMatrixWorld(true)

      // Foot.L 은 LowerLeg.L의 자식이 아닌 독립 Bone.
      // 따라서 종아리의 끝 지점에 발을 배치하여 발목이 분리되지 않게 한다.
      const kneeWorld = leg.lower.getWorldPosition(vec())
      const shinWorld = leg.shinAxis.clone()
        .applyQuaternion(leg.lower.getWorldQuaternion(quat()))
        .normalize()
      const targetWorld = kneeWorld.addScaledVector(shinWorld, leg.lowerLength)
      const shift = targetWorld.clone().sub(originalFootWorld)

      // 측정 실패/모델 호환성 문제로 발이 멀리 튀는 것을 차단한다.
      // 보정 이동은 캐릭터 높이 1.9 기준 0.7 이내로 제한한다.
      if (Number.isFinite(shift.length()) && shift.length() <= 0.70 &&
          shift.y >= -0.06 && shift.y <= 0.42) {
        leg.foot.parent.updateWorldMatrix(true, false)
        leg.foot.position.copy(leg.foot.parent.worldToLocal(targetWorld.clone()))
      } else {
        // 더 안전한 복귀: 원래 발을 유지하고 과도한 다리 회전을 제거한다.
        leg.upper.quaternion.copy(originalUpperQuaternion)
        leg.lower.quaternion.copy(originalLowerQuaternion)
        this.character.updateMatrixWorld(true)
        this.lastFootHeight = this.legs.map((item) => item.foot.getWorldPosition(vec()).y)
        if (!this.lastSafetyWarning || performance.now() - this.lastSafetyWarning > 2000) {
          console.warn('[LegPreview v9] unsafe leg lift prevented', shift.toArray())
          this.lastSafetyWarning = performance.now()
        }
        return
      }
      this.character.updateMatrixWorld(true)
      this.lastFootHeight = this.legs.map((item) => item.foot.getWorldPosition(vec()).y)
      return
    }

    if (mode === 'squat') {
      const meanLegLength = this.legs.reduce((sum, leg) => sum + leg.upperLength + leg.lowerLength, 0) / 2
      // v7 0.19 이하 -> v8 최대 0.30 장면 단위 (깊은 스쿼트이되 과도한 골반 침하 제한)
      const drop = Math.min(0.30, meanLegLength * 0.31)
      // 부모는 원본 애니메이션(Body.translation)을 매 프레임 갱신하므로 누적 이동하지 않음.
      const bodyParentScale = this.body.parent.getWorldScale(vec())
      this.body.position.y -= drop * strength / Math.max(1e-5, Math.abs(bodyParentScale.y))
      // 골반은 약간 뒤로 이동. 발은 독립 Foot Bone이어서 제자리에 남는다.
      this.body.position.z -= 0.065 * strength / Math.max(1e-5, Math.abs(bodyParentScale.z))
      this.character.updateMatrixWorld(true)
      // Hips는 상체 쪽 자식이며, 다리는 Body의 별도 자식.
      // Hips를 숙여도 양쪽 허벅지의 IK 계산을 방해하지 않는다.
      const torsoLean = quat().setFromAxisAngle(new THREE.Vector3(1, 0, 0), 0.16 * strength)
      this.hips.quaternion.copy(this.baseHipsQuaternion).premultiply(torsoLean).normalize()
    }
    this.character.updateMatrixWorld(true)

    for (const leg of this.legs) {
      // 스쿼트에서는 양발의 위치·회전을 직접 건드리지 않는다.
      this.character.updateMatrixWorld(true)
      const hip = leg.upper.getWorldPosition(vec())
      const ankle = leg.foot.getWorldPosition(vec())
      const knee = solveKnee(hip, ankle, leg.upperLength, leg.lowerLength, forward)
      if (!knee) continue
      // GLTF의 UpperLeg->LowerLeg 자식 방향을 사용하여 허벅지 방향 제어.
      aimBone(leg.upper, leg.lower.position.clone().normalize(), knee.clone().sub(hip), strength * 0.97)
      this.character.updateMatrixWorld(true)
      const realKnee = leg.lower.getWorldPosition(vec())
      aimBone(leg.lower, leg.shinAxis, ankle.clone().sub(realKnee), strength * 0.97)
    }
    this.character.updateMatrixWorld(true)
    this.lastFootHeight = this.legs.map((leg) => leg.foot.getWorldPosition(vec()).y)
  }
}
