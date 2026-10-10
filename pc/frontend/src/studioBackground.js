import * as THREE from 'three'

// A lightweight presentation room. Only decoration is created here;
// the nine tracking zones, character, pose rig and P10 chair stay in main.js.
export function createStudioBackground(scene) {
  scene.background = new THREE.Color(0x0c1821)
  scene.fog = new THREE.Fog(0x0c1821, 11, 20)

  const room = new THREE.Group()
  room.name = 'WiSensingStudioBackground'
  scene.add(room)

  const floorMat = new THREE.MeshStandardMaterial({
    color: 0x26343d, roughness: 0.91, metalness: 0.08
  })
  const matFloor = new THREE.Mesh(
    new THREE.PlaneGeometry(9, 8), floorMat
  )
  matFloor.rotation.x = -Math.PI / 2
  matFloor.receiveShadow = true
  room.add(matFloor)

  // Matte tracking area keeps the 9 cyan zone outlines legible.
  const trackingMat = new THREE.Mesh(
    new THREE.PlaneGeometry(4.95, 4.95),
    new THREE.MeshStandardMaterial({
      color: 0x1c2b34, roughness: 0.94, metalness: 0.04
    })
  )
  trackingMat.rotation.x = -Math.PI / 2
  trackingMat.position.y = 0.007
  trackingMat.receiveShadow = true
  room.add(trackingMat)

  const wallMat = new THREE.MeshStandardMaterial({
    color: 0x1a2832, roughness: 0.96
  })
  const sideMat = new THREE.MeshStandardMaterial({
    color: 0x15232c, roughness: 0.96, side: THREE.DoubleSide
  })
  const rear = new THREE.Mesh(new THREE.PlaneGeometry(9, 4.5), wallMat)
  rear.position.set(0, 2.25, -4)
  rear.receiveShadow = true
  room.add(rear)

  const left = new THREE.Mesh(new THREE.PlaneGeometry(8, 4.5), sideMat)
  left.rotation.y = Math.PI / 2
  left.position.set(-4.5, 2.25, 0)
  left.receiveShadow = true
  room.add(left)

  const trimMat = new THREE.MeshStandardMaterial({
    color: 0x344954, roughness: 0.63, metalness: 0.3
  })
  const panelMat = new THREE.MeshStandardMaterial({
    color: 0x22333e, roughness: 0.81, metalness: 0.17
  })
  const glowMat = new THREE.MeshBasicMaterial({
    color: 0x35abb9, transparent: true, opacity: 0.55,
    depthWrite: false
  })

  function block(w, h, d, x, y, z, material) {
    const item = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), material)
    item.position.set(x, y, z)
    room.add(item)
    return item
  }

  // Back-wall acoustic panels create room depth without blocking the avatar.
  for (const x of [-3.52, -1.76, 0, 1.76, 3.52]) {
    block(1.55, 2.65, 0.065, x, 2.03, -3.945, panelMat)
    block(1.47, 0.025, 0.072, x, 3.37, -3.900, trimMat)
  }
  block(9, 0.095, 0.15, 0, 0.16, -3.89, trimMat)
  block(9, 0.06, 0.11, 0, 4.13, -3.92, trimMat)
  block(8, 0.065, 0.1, -4.41, 0.16, 0, trimMat)

  // Indirect accent lines stay behind the occupied 3x3 detection area.
  for (const x of [-4.02, 4.02]) {
    block(0.035, 2.6, 0.04, x, 2.12, -3.89, glowMat)
  }
  block(7.95, 0.035, 0.035, 0, 4.02, -3.86, glowMat)

  const guideMat = new THREE.MeshBasicMaterial({
    color: 0x2b606b, transparent: true, opacity: 0.49,
    depthWrite: false
  })
  for (const edge of [-2.48, 2.48]) {
    block(5.02, 0.012, 0.018, 0, 0.019, edge, guideMat)
    block(0.018, 0.012, 5.02, edge, 0.019, 0, guideMat)
  }

  // Wall-mounted brand sign. Texture is generated locally, with no image assets.
  const canvas = document.createElement('canvas')
  canvas.width = 1024
  canvas.height = 256
  const ctx = canvas.getContext('2d')
  if (ctx) {
    ctx.textAlign = 'center'
    ctx.fillStyle = '#e9f8fb'
    ctx.font = '700 112px Arial, sans-serif'
    ctx.fillText('WiSensing', 512, 132)
    ctx.fillStyle = '#60ccd3'
    ctx.font = '500 37px Arial, sans-serif'
    ctx.fillText('CSI  /  POSE + POSITION', 512, 197)
    const texture = new THREE.CanvasTexture(canvas)
    texture.colorSpace = THREE.SRGBColorSpace
    const label = new THREE.Sprite(new THREE.SpriteMaterial({
      map: texture, transparent: true, depthWrite: false
    }))
    label.scale.set(2.3, 0.575, 1)
    label.position.set(2.56, 3.5, -3.78)
    room.add(label)
  }

  return room
}
