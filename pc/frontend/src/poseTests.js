// 화면/GLTF 리깅 시험용 인공 2D 좌표. 실제 CNN 출력이 아닙니다.
// MediaPipe IDs: 어깨 11/12, 팔꿈치 13/14, 손목 15/16,
// 엉덩이 23/24, 무릎 25/26, 발목 27/28.
export const TEST_POSES = Object.freeze({
  stand: {
    label: '기본 서기',
    hint: 'S · 원래 Idle 애니메이션을 재생합니다. 발이 바닥에 붙어 있고 다리가 똑바로 서는지 확인하세요.'
  },
  armUp: {
    label: '한 팔 올리기',
    hint: 'Q · 화면 오른쪽 팔을 듭니다. Pose 패널과 캐릭터의 팔 방향을 비교하세요.'
  },
  armsWide: {
    label: '양팔 벌리기',
    hint: 'W · 양팔을 좌우로 펼칩니다. 양쪽 위팔·아래팔의 반응을 확인하세요.'
  },
  squat: {
    label: '스쿼트',
    hint: 'E · 오른쪽 12관절의 다리 각도를 3D에서도 사용합니다. 무릎의 앞쪽 굽힘은 깊이를 가정한 시각화입니다.'
  },
  legLift: {
    label: '다리 들기',
    hint: 'R · Pose Result와 동일한 무릎/발목 방향으로 다리를 움직입니다. V로 앞뒤 깊이 가정을 확인하세요.'
  }
})

const IDS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
const BASE = {
  11: [0.40, 0.20], 12: [0.60, 0.20],
  13: [0.30, 0.38], 14: [0.70, 0.38],
  15: [0.24, 0.56], 16: [0.76, 0.56],
  23: [0.43, 0.54], 24: [0.57, 0.54],
  25: [0.41, 0.73], 26: [0.59, 0.73],
  27: [0.40, 0.94], 28: [0.60, 0.94]
}

const OFFSETS = {
  stand: {},
  armUp: {
    13: [0.27, 0.13], 15: [0.17, 0.02]
  },
  armsWide: {
    13: [0.24, 0.22], 15: [0.06, 0.24],
    14: [0.76, 0.22], 16: [0.94, 0.24]
  },
  squat: {
    // 전면 2D 투영: 무릎이 좌우로 벌어지지 않도록 거의 제자리에 둔다.
    // 허리를 내리고 다리의 화면상 길이를 줄인다. 굽힘의 깊이는 3D에서만 근사한다.
    11: [0.40, 0.31], 12: [0.60, 0.31],
    13: [0.30, 0.48], 14: [0.70, 0.48],
    15: [0.24, 0.64], 16: [0.76, 0.64],
    23: [0.43, 0.65], 24: [0.57, 0.65],
    25: [0.42, 0.78], 26: [0.58, 0.78],
    27: [0.40, 0.94], 28: [0.60, 0.94]
  },
  legLift: {
    // The left knee and ankle rise visibly; modest lateral displacement.
    // Front/back depth is inferred by PoseRig for visual demonstration.
    25: [0.34, 0.58], 27: [0.35, 0.69]
  }
}

export function createTestPose(name) {
  if (!TEST_POSES[name]) throw new Error(`Unknown test pose: ${name}`)
  const changes = OFFSETS[name]
  return {
    valid: true,
    coordinate_space: 'fake_normalized',
    test_pose: name,
    joints: IDS.map((id) => {
      const [x, y] = changes[id] ?? BASE[id]
      return { id, x, y }
    })
  }
}
