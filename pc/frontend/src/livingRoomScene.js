import * as THREE from 'three'
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js'

const MATERIALS = Object.freeze({
  accent: 0x55dff8,
  tile: 0x132334,
  inactive: 0x4a9eb5,
  selected: 0x48e9ff
})

const SEPARATOR = 1.45

function basic(color, options = {}) {
  return new THREE.MeshBasicMaterial({ color, ...options })
}
function standard(color, options = {}) {
  return new THREE.MeshStandardMaterial({ color, roughness: 0.8, ...options })
}
function box(parent, width, height, depth, x, y, z, material, shadow = false) {
  const object = new THREE.Mesh(new THREE.BoxGeometry(width, height, depth), material)
  object.position.set(x, y, z)
  object.castShadow = shadow
  object.receiveShadow = true
  parent.add(object)
  return object
}
function cylinder(parent, upper, lower, height, x, y, z, material, segments = 16) {
  const object = new THREE.Mesh(new THREE.CylinderGeometry(upper, lower, height, segments), material)
  object.position.set(x, y, z)
  object.castShadow = false
  object.receiveShadow = true
  parent.add(object)
  return object
}
function flat(parent, width, height, x, y, z, material) {
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height), material)
  mesh.rotation.x = -Math.PI / 2
  mesh.position.set(x, y, z)
  mesh.receiveShadow = true
  parent.add(mesh)
  return mesh
}
function softBox(parent, width, height, depth, x, y, z, material, radius = 0.065) {
  const r = Math.min(radius, width * 0.35, height * 0.35, depth * 0.35)
  const mesh = new THREE.Mesh(new RoundedBoxGeometry(width, height, depth, 4, r), material)
  mesh.position.set(x, y, z)
  mesh.castShadow = true
  mesh.receiveShadow = true
  parent.add(mesh)
  return mesh
}

function plasterMap(top, middle, bottom) {
  const c = document.createElement('canvas')
  c.width = c.height = 512
  const ctx = c.getContext('2d')
  const gradient = ctx.createLinearGradient(0, 0, 0, 512)
  gradient.addColorStop(0, top)
  gradient.addColorStop(0.45, middle)
  gradient.addColorStop(1, bottom)
  ctx.fillStyle = gradient
  ctx.fillRect(0, 0, 512, 512)
  let seed = 8191
  function random() {
    seed = (seed * 1664525 + 1013904223) >>> 0
    return seed / 4294967296
  }
  for (let i = 0; i < 19000; i++) {
    const x = random() * 512
    const y = random() * 512
    const w = 1 + random() * 4
    const h = 1 + random() * 6
    ctx.fillStyle = random() > 0.5 ? 'rgba(244,191,151,0.05)' : 'rgba(0,0,0,0.042)'
    ctx.fillRect(x, y, w, h)
  }
  for (let i = 0; i < 130; i++) {
    const y = 20 + i * 3.7
    ctx.strokeStyle = 'rgba(255,255,255,0.012)'
    ctx.beginPath()
    ctx.moveTo(0, y)
    ctx.lineTo(512, y + 22)
    ctx.stroke()
  }
  const tex = new THREE.CanvasTexture(c)
  tex.name = 'plaster'
  tex.colorSpace = THREE.SRGBColorSpace
  tex.anisotropy = 4
  return tex
}

function pictureTexture(name, painter) {
  const cached = TEXTURES.get(name)
  if (cached) return cached
  const c = document.createElement('canvas')
  c.width = 500
  c.height = 400
  const ctx = c.getContext('2d')
  painter(ctx, c.width, c.height)
  const t = new THREE.CanvasTexture(c)
  t.name = name
  t.colorSpace = THREE.SRGBColorSpace
  TEXTURES.set(name, t)
  return t
}

function pictureMapAbstract() {
  return pictureTexture('picture-abstract-midcentury', (ctx, w, h) => {
    const g = ctx.createLinearGradient(0, 0, w, h)
    g.addColorStop(0, '#ead9bc')
    g.addColorStop(0.55, '#c7b296')
    g.addColorStop(1, '#92a097')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = '#264048'
    ctx.fillRect(54, 72, 172, 260)
    ctx.fillStyle = '#ca7a61'
    ctx.fillRect(196, 40, 168, 220)
    ctx.fillStyle = '#bcc4b4'
    ctx.fillRect(308, 176, 144, 170)
    ctx.fillStyle = '#ebd1a0'
    ctx.beginPath(); ctx.arc(310, 124, 72, 0, Math.PI * 2); ctx.fill()
    ctx.fillStyle = '#24373c'
    ctx.beginPath(); ctx.moveTo(82, 378); ctx.lineTo(236, 198); ctx.lineTo(412, 378); ctx.fill()
    ctx.strokeStyle = 'rgba(250,240,213,0.55)'
    ctx.lineWidth = 7
    ctx.beginPath(); ctx.arc(352, 292, 55, -Math.PI * 0.8, Math.PI * 0.18); ctx.stroke()
  })
}

function pictureMapLandscape() {
  return pictureTexture('picture-landscape-warm-hills', (ctx, w, h) => {
    const sky = ctx.createLinearGradient(0, 0, 0, h)
    sky.addColorStop(0, '#d8d4c8')
    sky.addColorStop(0.48, '#efe7d5')
    sky.addColorStop(1, '#f5ecd8')
    ctx.fillStyle = sky
    ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = '#ced6d3'
    ctx.fillRect(0, h * 0.55, w, h * 0.45)
    const sun = ctx.createRadialGradient(364, 96, 8, 364, 96, 62)
    sun.addColorStop(0, 'rgba(248,225,168,0.95)')
    sun.addColorStop(1, 'rgba(248,225,168,0)')
    ctx.fillStyle = sun
    ctx.fillRect(288, 24, 148, 148)
    ctx.fillStyle = '#dcb992'
    ctx.beginPath(); ctx.arc(360, 92, 36, 0, Math.PI * 2); ctx.fill()
    ctx.fillStyle = '#98a388'
    ctx.beginPath(); ctx.moveTo(0, 252); ctx.quadraticCurveTo(118, 170, 256, 232); ctx.quadraticCurveTo(370, 274, 500, 214); ctx.lineTo(500, 400); ctx.lineTo(0, 400); ctx.fill()
    ctx.fillStyle = '#627464'
    ctx.beginPath(); ctx.moveTo(0, 304); ctx.quadraticCurveTo(124, 246, 230, 282); ctx.quadraticCurveTo(342, 336, 500, 280); ctx.lineTo(500, 400); ctx.lineTo(0, 400); ctx.fill()
    ctx.fillStyle = '#40554d'
    ctx.beginPath(); ctx.moveTo(0, 350); ctx.quadraticCurveTo(130, 292, 246, 320); ctx.quadraticCurveTo(390, 362, 500, 330); ctx.lineTo(500, 400); ctx.lineTo(0, 400); ctx.fill()
    ctx.strokeStyle = 'rgba(255,255,255,0.45)'
    ctx.lineWidth = 3
    ctx.beginPath(); ctx.moveTo(58, 300); ctx.quadraticCurveTo(168, 330, 290, 310); ctx.quadraticCurveTo(386, 294, 474, 322); ctx.stroke()
  })
}

function pictureMapBotanical() {
  return pictureTexture('picture-botanical-line', (ctx, w, h) => {
    const g = ctx.createLinearGradient(0, 0, w, h)
    g.addColorStop(0, '#f0eadf')
    g.addColorStop(1, '#ddd5c7')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, w, h)
    ctx.strokeStyle = '#345247'
    ctx.lineWidth = 6
    ctx.lineCap = 'round'
    ctx.beginPath(); ctx.moveTo(244, 362); ctx.quadraticCurveTo(250, 260, 224, 192); ctx.quadraticCurveTo(202, 130, 216, 68); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(246, 330); ctx.quadraticCurveTo(290, 300, 322, 246); ctx.quadraticCurveTo(348, 202, 360, 150); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(236, 276); ctx.quadraticCurveTo(184, 242, 164, 184); ctx.quadraticCurveTo(150, 144, 152, 104); ctx.stroke()
    ctx.strokeStyle = '#708971'
    ctx.lineWidth = 4
    for (const [x, y, rx, ry, rot] of [[194,180,54,26,-0.65],[154,116,42,20,-0.2],[310,248,58,26,-0.55],[356,154,46,21,-0.3],[214,120,40,18,0.55],[174,226,48,22,0.35]]) {
      ctx.beginPath(); ctx.ellipse(x, y, rx, ry, rot, 0, Math.PI*2); ctx.stroke()
    }
    ctx.fillStyle = '#c69264'
    ctx.beginPath(); ctx.arc(374, 76, 26, 0, Math.PI * 2); ctx.fill()
    ctx.strokeStyle = 'rgba(210,171,134,0.65)'
    ctx.lineWidth = 2
    ctx.beginPath(); ctx.arc(374, 76, 40, 0.1, Math.PI * 0.95); ctx.stroke()
  })
}

function floorMap() {
  // Irregular, warm charcoal limestone tiles. Each tile receives subtle grain,
  // veins and diffuse lighting, rather than repeated strong rectangular borders.
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = 1024
  const ctx = canvas.getContext('2d')
  const rand = randomFactory(39027)
  ctx.fillStyle = '#2d2d30'
  ctx.fillRect(0, 0, 1024, 1024)
  const columns = 6, rows = 6, width = 1024 / columns, height = 1024 / rows
  const colors = ['#494542','#444340','#403f40','#494746','#424345','#4c4946','#454544','#484744']
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < columns; col++) {
      const left = col * width + 2.4
      const top = row * height + 2.4
      const w = width - 4.8, h = height - 4.8
      ctx.fillStyle = colors[Math.floor(rand() * colors.length)]
      ctx.fillRect(left, top, w, h)
      const softShade = ctx.createLinearGradient(left, top, left + w, top + h)
      softShade.addColorStop(0, 'rgba(255,235,208,0.045)')
      softShade.addColorStop(0.5, 'rgba(255,255,255,0.010)')
      softShade.addColorStop(1, 'rgba(0,0,0,0.060)')
      ctx.fillStyle = softShade
      ctx.fillRect(left, top, w, h)
      ctx.save()
      ctx.beginPath()
      ctx.rect(left + 1, top + 1, w - 2, h - 2)
      ctx.clip()
      // Natural mineral flecks and very light veining, deterministic per reload.
      for (let k = 0; k < 72; k++) {
        ctx.fillStyle = rand() > 0.5 ? 'rgba(218,208,198,0.025)' : 'rgba(9,15,19,0.025)'
        ctx.fillRect(left + rand() * w, top + rand() * h, 0.5 + rand() * 4, 0.5 + rand() * 1.8)
      }
      for (let k = 0; k < 3; k++) {
        const x = left + rand() * w
        const y = top + rand() * h
        ctx.beginPath()
        ctx.moveTo(x - 36, y - 24)
        ctx.bezierCurveTo(x - 4, y + 12, x + 23, y + 4, x + 60, y + 39)
        ctx.strokeStyle = rand() > .3 ? 'rgba(209,200,180,0.045)' : 'rgba(0,0,0,0.045)'
        ctx.lineWidth = 0.5 + rand() * 1.4
        ctx.stroke()
      }
      ctx.restore()
    }
  }
  const tex = new THREE.CanvasTexture(canvas)
  tex.name = 'warm-limestone-floor-v8'
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping
  tex.repeat.set(1.85, 1.85)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.anisotropy = 8
  return tex
}

// Deterministic textures: no external assets or network downloads.
// Texture cache prevents duplicate large canvases / GPU uploads.
const TEXTURES = new Map()
function cachedTexture(name, size, painter, repeatX = 1, repeatY = 1) {
  if (TEXTURES.has(name)) return TEXTURES.get(name)
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = size
  const ctx = canvas.getContext('2d')
  painter(ctx, size)
  const tex = new THREE.CanvasTexture(canvas)
  tex.name = name
  tex.colorSpace = THREE.SRGBColorSpace
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping
  tex.repeat.set(repeatX, repeatY)
  tex.anisotropy = 8
  TEXTURES.set(name, tex)
  return tex
}
function randomFactory(seed) {
  return () => { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 4294967296 }
}
function woodMap() {
  return cachedTexture('warm-oak', 512, (ctx, size) => {
    const r = randomFactory(20082)
    ctx.fillStyle = '#987057'; ctx.fillRect(0, 0, size, size)
    for (let x = 0; x < size; x += 1.5) {
      const wobble = 12 * Math.sin(x * .031) + 5 * Math.sin(x * .097)
      const shade = Math.round(130 + 22 * Math.sin(x * .07 + wobble) + r()*15)
      ctx.strokeStyle = `rgba(${shade},${Math.round(shade*.73)},${Math.round(shade*.52)},${.06+r()*.18})`
      ctx.beginPath()
      ctx.moveTo(x, 0)
      ctx.bezierCurveTo(x+3, 120, x-4, 390, x+Math.sin(x*.1)*4, 512)
      ctx.stroke()
    }
    for(let i=0;i<26;i++) {
      const x=r()*size,y=r()*size
      ctx.strokeStyle='rgba(57,35,26,0.14)'; ctx.lineWidth=.8
      ctx.beginPath();ctx.ellipse(x,y,8+r()*8,26+r()*38,r()*.32,0,Math.PI*2);ctx.stroke()
    }
  }, 1, 1)
}
function stoneMap() {
  return cachedTexture('ivory-travertine', 512, (ctx, size) => {
    const r=randomFactory(47852)
    const grad=ctx.createLinearGradient(0,0,size,size)
    grad.addColorStop(0,'#e1d7c6'); grad.addColorStop(.5,'#b9ad9b'); grad.addColorStop(1,'#ded2bd')
    ctx.fillStyle=grad;ctx.fillRect(0,0,size,size)
    for(let i=0;i<28;i++) {
      const bx=r()*512,by=r()*512
      ctx.beginPath();ctx.moveTo(bx-35,by-70)
      ctx.bezierCurveTo(bx+33,by+60,bx-50,by+155,bx+140,by+260)
      ctx.strokeStyle=i%3?'rgba(120,104,88,0.09)':'rgba(255,255,255,0.34)'
      ctx.lineWidth=.7+r()*2;ctx.stroke()
    }
    for(let i=0;i<4200;i++) {
      ctx.fillStyle=r()>.5?'rgba(89,77,70,0.025)':'rgba(255,255,255,0.06)'
      ctx.fillRect(r()*512,r()*512,1+r()*2,1+r()*2)
    }
  })
}
function wovenMap() {
  return cachedTexture('woven-linen', 256, (ctx, size) => {
    ctx.fillStyle='#ded1be';ctx.fillRect(0,0,size,size)
    for(let i=0;i<size;i+=3) {
      ctx.strokeStyle=i%2?'rgba(107,92,75,.095)':'rgba(255,255,255,.16)'
      ctx.beginPath();ctx.moveTo(i,0);ctx.lineTo(i,size);ctx.stroke()
      ctx.beginPath();ctx.moveTo(0,i);ctx.lineTo(size,i);ctx.stroke()
    }
  }, 2, 2)
}
function glowBox(parent, width, height, depth, x, y, z, hex=0xffc58b) {
  return box(parent,width,height,depth,x,y,z,standard(hex,{
    emissive:hex, emissiveIntensity:.72, roughness:.9
  }))
}
function clayVase(parent,x,y,z,color=0xbab0a3,scale=1) {
  const base=standard(color,{roughness:.86})
  const obj=cylinder(parent,.105*scale,.15*scale,.22*scale,x,y+.11*scale,z,base,16)
  cylinder(parent,.09*scale,.085*scale,.035*scale,x,y+.24*scale,z,base,16)
  return obj
}
function smallBooks(parent,x,y,z,width=.34) {
  const palette=[0x746b5a,0x455d5b,0x9d806d,0x353d40,0xc5b39b]
  for(let i=0;i<5;i++) {
    const w=width/5-.006
    box(parent,w,.20+.035*(i%3),.15,x-width/2+i*width/5+w/2,y+.1,z,
      standard(palette[i],{roughness:.93}))
  }
}
function shelfBooks(parent,x,surfaceY,z,width=.34,depth=.14) {
  const palette=[0x746b5a,0x455d5b,0x9d806d,0x353d40,0xc5b39b]
  const heights=[.18,.22,.24,.19,.21]
  for(let i=0;i<5;i++) {
    const w=width/5-.006
    const h=heights[i]
    box(parent,w,h,depth,x-width/2+i*width/5+w/2,surfaceY+h/2,z,
      standard(palette[i],{roughness:.93}))
  }
}
function littlePlant(parent,x,y,z,size=.43) {
  const pot=standard(0xcebaa1,{roughness:.89})
  cylinder(parent,.14*size,.11*size,.19*size,x,y+.095*size,z,pot,14)
  const green=standard(0x4a7251,{roughness:.96,side:THREE.DoubleSide})
  for(let i=0;i<6;i++) {
    const a=i*Math.PI/3
    const leaf=new THREE.Mesh(new THREE.SphereGeometry(.15*size,7,5),green)
    leaf.scale.set(.55,1.30,.45)
    leaf.position.set(x+Math.cos(a)*.10*size,y+.34*size,z+Math.sin(a)*.10*size)
    leaf.rotation.z=Math.cos(a)*.58
    parent.add(leaf)
  }
}
function glowOrb(parent,x,y,z,r=.12) {
  const mesh=new THREE.Mesh(new THREE.SphereGeometry(r,16,12),standard(0xffe4b2,{
    emissive:0xffbe75,emissiveIntensity:.75,roughness:.96
  }))
  mesh.position.set(x,y,z);parent.add(mesh)
  return mesh
}


function makeSofa(room) {
  const sofa=new THREE.Group()
  sofa.name='LeftSofa'
  sofa.position.set(-3.66,0,-3.54)
  sofa.rotation.y=.16
  room.add(sofa)
  const linen=standard(0xe4d9cd,{map:wovenMap(),roughness:.98})
  const base=standard(0xb9ada0,{roughness:.94})
  const legs=standard(0x483b36,{roughness:.73})
  const cushionMaterials=[standard(0x98705e,{roughness:.94}),standard(0x71806c,{roughness:.97}),standard(0xb8a596,{roughness:.99})]

  softBox(sofa,2.16,.30,.96,0,.36,0,base,.10)
  softBox(sofa,2.12,.69,.20,0,.85,-.43,linen,.09)
  for(const side of [-1,1]) {
    softBox(sofa,.19,.48,.91,side*.99,.61,.02,linen,.068)
    for(const zz of [-.28,.30])box(sofa,.09,.13,.09,side*.88,.125,zz,legs,true)
  }
  for(const x of [-.63,0,.63]) {
    softBox(sofa,.65,.19,.72,x,.56,.07,linen,.070)
    const back=softBox(sofa,.63,.48,.15,x,.86,-.22,linen,.065)
    back.rotation.x=-.045
  }
  for(const [i,x,z] of [[0,-.64,.23],[1,.03,.18],[2,.65,.22]]) {
    const p=softBox(sofa,.29,.32,.11,x,.81,z,cushionMaterials[i],.057)
    p.rotation.z=(i-1)*.13
  }
  const rug=flat(room,2.53,1.50,-3.62,.018,-3.02,
    standard(0xffffff,{map:wovenMap(),roughness:1,side:THREE.DoubleSide}))
  rug.rotation.z=.07
  const table=new THREE.Group()
  table.name='SofaCoffeeTable'
  table.position.set(-3.27,0,-2.38)
  table.rotation.y=-.18
  room.add(table)
  const wood=standard(0xa07c60,{map:woodMap(),roughness:.69})
  const dark=standard(0x2b2d30,{metalness:.26,roughness:.52})
  const top=cylinder(table,.345,.345,.065,0,.38,0,wood,48)
  top.castShadow=true
  for(const x of [-.22,.22])for(const z of [-.13,.13])cylinder(table,.018,.018,.33,x,.195,z,dark,10)
  smallBooks(table,-.11,.415,0,.21)
  littlePlant(table,.12,.415,-.08,.53)
  cylinder(table,.075,.075,.025,.13,.422,.10,standard(0xe7cbb0),24)
  const sideCab=new THREE.Group()
  sideCab.position.set(-5.04,0,-3.16)
  room.add(sideCab)
  box(sideCab,.43,.62,.56,0,.33,0,wood,true)
  box(sideCab,.46,.07,.58,0,.68,0,standard(0xba906f,{map:woodMap()}))
  glowOrb(sideCab,0,.84,0,.13)
}

function plant(room, x, z, scale = 1, rot = 0) {
  const group = new THREE.Group()
  group.position.set(x, 0, z)
  group.rotation.y = rot
  room.add(group)
  const planter = standard(0x343b3b, { roughness: 0.85 })
  const stemMat = standard(0x514f31)
  const leafMat = [standard(0x284b3e, { roughness: 0.95 }), standard(0x3d6650, { roughness: 0.95 })]
  cylinder(group, 0.20 * scale, 0.16 * scale, 0.33 * scale, 0, 0.18 * scale, 0, planter)
  for (let j = 0; j < 12; j++) {
    const a = (j * 2.39996)
    const radius = (0.21 + (j % 3) * 0.105) * scale
    const height = (0.69 + (j % 5) * 0.16) * scale
    const tx = Math.cos(a) * radius
    const tz = Math.sin(a) * radius
    const cx = Math.cos(a) * radius * 0.56
    const cz = Math.sin(a) * radius * 0.56
    const dir = new THREE.Vector3(tx, height - 0.38 * scale, tz)
    const stem = new THREE.Mesh(new THREE.CylinderGeometry(0.011 * scale, 0.014 * scale, dir.length(), 5), stemMat)
    stem.position.set(cx, (height + 0.38 * scale) * 0.5, cz)
    stem.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.normalize())
    group.add(stem)
    const leaf = new THREE.Mesh(new THREE.SphereGeometry(0.13 * scale, 7, 5), leafMat[j % 2])
    leaf.scale.set(0.65, 1.9, 0.40)
    leaf.rotation.z = Math.cos(a) * 0.72
    leaf.rotation.x = Math.sin(a) * 0.40
    leaf.position.set(tx, height, tz)
    group.add(leaf)
  }
}

function lamp(room, x, z) {
  const metal = standard(0x927968, { roughness: 0.48, metalness: 0.34 })
  cylinder(room, 0.19, 0.19, 0.035, x, 0.030, z, metal)
  cylinder(room, 0.018, 0.018, 1.43, x, 0.748, z, metal)
  const shade = cylinder(room, 0.22, 0.28, 0.35, x, 1.52, z,
    standard(0xf7d2a0, { emissive: 0xf5ab56, emissiveIntensity: 0.38, roughness: 0.95 }), 24)
  shade.castShadow = false
  const light = new THREE.PointLight(0xffb66c, 15, 3.5, 2)
  light.position.set(x, 1.39, z)
  room.add(light)
}

function makeWindows(room) {
  const canvas=document.createElement('canvas')
  canvas.width=canvas.height=768
  const ctx=canvas.getContext('2d')
  const sky=ctx.createLinearGradient(0,0,0,768)
  sky.addColorStop(0,'#07101f');sky.addColorStop(.46,'#0a1f38');sky.addColorStop(.80,'#12345a');sky.addColorStop(1,'#21486b')
  ctx.fillStyle=sky;ctx.fillRect(0,0,768,768)
  // subtle haze near the horizon
  const haze=ctx.createLinearGradient(0,330,0,768)
  haze.addColorStop(0,'rgba(100,155,210,0)')
  haze.addColorStop(1,'rgba(120,170,220,0.20)')
  ctx.fillStyle=haze;ctx.fillRect(0,330,768,438)
  const rand=randomFactory(34761)
  const layers=[
    {count:9, base:'#183553', minW:52, maxW:92, minH:150, maxH:260, offset:48, alpha:.95},
    {count:7, base:'#102740', minW:58, maxW:110, minH:240, maxH:390, offset:18, alpha:1},
    {count:5, base:'#0a1b30', minW:72, maxW:132, minH:320, maxH:520, offset:-8, alpha:1}
  ]
  layers.forEach((cfg,layer)=>{
    for(let i=0;i<cfg.count;i++){
      const width=cfg.minW+Math.round(rand()*(cfg.maxW-cfg.minW))
      const height=cfg.minH+Math.round(rand()*(cfg.maxH-cfg.minH))
      const spacing=768/cfg.count
      const x=Math.max(0,Math.min(768-width,(i*spacing)+(rand()*34-17)+layer*8))
      const y=768-height-cfg.offset
      ctx.globalAlpha=cfg.alpha
      ctx.fillStyle=cfg.base
      ctx.fillRect(x,y,width,height)
      if(rand()>.45){ ctx.fillRect(x+width*0.14,y-5,width*0.34,5) }
      if(height>360 && rand()>.42){
        ctx.fillStyle=cfg.base
        ctx.fillRect(x+width*.50,y-20,3,20)
      }
      const stepX=12+layer*1.5, stepY=20+layer*1.5
      for(let row=0;row<Math.floor(height/stepY);row++)for(let col=0;col<Math.floor(width/stepX);col++){
        if(rand()<.42)continue
        ctx.fillStyle=rand()<.88?'#f2c67a':'#9cc4d6'
        ctx.globalAlpha=.28+rand()*.58
        ctx.fillRect(x+6+col*stepX,y+10+row*stepY,3.4,4.7)
      }
      if(height>320 && rand()>.28){
        ctx.globalAlpha=.95
        ctx.fillStyle='#d54d4f'
        ctx.beginPath(); ctx.arc(x+width*.5,y+6,2.6,0,Math.PI*2); ctx.fill()
      }
    }
  })
  ctx.globalAlpha=1
  ;[
    {x:146,w:86,h:430,c:'#0a1b30'},
    {x:388,w:94,h:470,c:'#09182a'},
    {x:612,w:78,h:400,c:'#102740'}
  ].forEach(t=>{
    const y=768-t.h-6
    ctx.fillStyle=t.c
    ctx.fillRect(t.x,y,t.w,t.h)
    for(let row=0;row<Math.floor(t.h/20);row++)for(let col=0;col<Math.floor(t.w/13);col++){
      if(rand()<.40)continue
      ctx.fillStyle=rand()<.90?'#f3c780':'#9bc6d8'
      ctx.globalAlpha=.30+rand()*.60
      ctx.fillRect(t.x+8+col*13,y+10+row*20,3.5,4.8)
    }
    ctx.globalAlpha=.92
    ctx.fillStyle='#d14f52'
    ctx.beginPath(); ctx.arc(t.x+t.w*.5,y+6,3,0,Math.PI*2); ctx.fill()
  })
  ctx.globalAlpha=1
  const texture=new THREE.CanvasTexture(canvas)
  texture.name='night-window'
  texture.colorSpace=THREE.SRGBColorSpace
  const win=new THREE.Group()
  win.name='FinishedRightWindow'
  win.position.set(3.24,2.34,-5.20)
  win.rotation.y=-.075
  room.add(win)
  const frame=standard(0x28262a,{roughness:.52,metalness:.20})
  const walnut=standard(0x775b4d,{map:woodMap(),roughness:.67})
  box(win,2.35,2.94,.13,0,0,-.05,frame,true)
  const glass=new THREE.Mesh(new THREE.PlaneGeometry(2.19,2.77),basic(0xffffff,{
    map:texture,side:THREE.DoubleSide,toneMapped:false
  }))
  glass.position.z=.035
  win.add(glass)
  for(const x of [-1.14,0,1.14])box(win,.078,2.86,.16,x,0,.12,frame,true)
  for(const y of [-1.39,0,1.39])box(win,2.34,.08,.16,0,y,.12,frame,true)
  box(win,2.60,.11,.42,0,-1.54,.27,walnut,true)
  for(const x of [-1.32,1.32])box(win,.12,3.10,.20,x,0,.06,walnut,true)
  box(win,2.65,.10,.19,0,1.54,.06,walnut)

  // Fabric curtains: anchored to the rail with a top band and side-stacked folds,
  // so they no longer appear to float in front of the window.
  const curtain=standard(0xc7b6a4,{map:wovenMap(),roughness:.98,side:THREE.DoubleSide})
  const rodMat=standard(0x8a725f,{metalness:.18,roughness:.58})
  box(win,2.92,.057,.10,0,1.58,.24,rodMat)
  for(const sign of [-1,1]){
    const panel=new THREE.Group()
    panel.position.set(sign*1.44,-.02,.15)
    win.add(panel)
    const xOffsets = sign < 0 ? [0.00,-0.06,-0.12,-0.18,-0.24] : [0.00,0.06,0.12,0.18,0.24]
    xOffsets.forEach((xx, k) => {
      const fold=softBox(panel,.11,2.76,.075,xx,0.00,-0.01 + Math.sin(k*0.8)*.016,curtain,.024)
      fold.rotation.z=sign*(0.018 + k*0.006)
      fold.castShadow=false
    })
    // top band connects the curtain to the rod and hides the floating gap.
    box(panel,.42,.10,.09,sign*0.11,1.34,0.01,curtain)
    // tie-back / weight detail near lower-middle part of each curtain.
    const brass=standard(0xa99476,{metalness:.45,roughness:.45})
    box(panel,.065,.17,.05,sign*0.08,-1.02,.06,brass)
    box(panel,.08,.08,.07,sign*0.08,-1.10,.06,brass)
  }

  const bench=new THREE.Group()
  bench.name='RightWindowBench'
  bench.position.set(3.64,0,-3.53)
  bench.rotation.y=-.10
  room.add(bench)
  box(bench,1.75,.44,.55,0,.29,0,standard(0x6f5141,{map:woodMap(),roughness:.75}),true)
  for(const x of [-.56,0,.56])box(bench,.026,.34,.57,x,.31,.012,standard(0x986d52,{map:woodMap()}))
  softBox(bench,1.73,.12,.56,0,.58,0,standard(0xd5c4b0,{map:wovenMap(),roughness:.99}),.04)
  softBox(bench,.30,.25,.12,.49,.72,-.07,standard(0x687b68,{roughness:.96}),.04)
  softBox(bench,.26,.24,.11,.08,.71,-.06,standard(0xe7dbcf,{roughness:.97}),.04)
  glowBox(bench,1.70,.018,.035,0,.055,.20,0xffc28a)
  // Window-side filler so the bench area does not feel empty.
  plant(room,4.78,-3.86,.86,-.10)
}

function makeKitchen(room) {
  // Conservative footprint: stays away from the window and the 3x3 tracking pad.
  const kitchen=new THREE.Group()
  kitchen.name='RecessedKitchen'
  kitchen.position.set(-.53,0,-5.0)
  room.add(kitchen)
  const wood=standard(0x997257,{map:woodMap(),roughness:.79})
  const frame=standard(0x584033,{roughness:.83})
  const inset=standard(0x765341,{map:woodMap(),roughness:.85})
  const stone=standard(0xe3d6c4,{map:stoneMap(),roughness:.48,metalness:.03})
  const metal=standard(0xc6a477,{metalness:.66,roughness:.33})

  // Cabinets use extruded carcasses, inset fronts and visible handles.
  box(kitchen,3.50,.87,.72,0,.66,-.015,frame,true)
  box(kitchen,3.62,.11,.86,0,1.14,.04,stone,true)
  box(kitchen,3.42,.15,.13,0,.18,.35,standard(0x3f302d))
  for(const x of [-1.28,-.43,.43,1.28]){
    box(kitchen,.78,.70,.075,x,.65,.395,wood,true)
    box(kitchen,.64,.57,.035,x,.65,.446,inset,true)
    box(kitchen,.23,.025,.062,x,.67,.492,metal)
    for(const dx of [-.37,.37])box(kitchen,.018,.70,.055,x+dx,.65,.476,frame)
  }
  // Marble panel is truly behind the open shelf, not hovering in front.
  box(kitchen,3.56,1.08,.060,0,1.85,-.345,stone,true)
  glowBox(kitchen,3.48,.025,.032,0,2.39,-.26,0xffc98f)
  const shelfWood=standard(0x73513f,{map:woodMap(),roughness:.73})
  box(kitchen,3.54,.068,.42,0,1.98,.005,shelfWood,true)
  box(kitchen,3.54,.062,.36,0,2.28,-.04,shelfWood,true)
  glowBox(kitchen,3.40,.018,.023,0,1.90,.19,0xffcd8f)

  // More realistic upper wall cabinets with cleaner door variation, crown and warm under-lighting.
  const upperDoorColors=[0x895f45,0x8f674c,0x956b50,0x865a41]
  for(const [i,x] of [[0,-1.25],[1,-.41],[2,.42],[3,1.25]]){
    const doorWood=standard(upperDoorColors[i],{map:woodMap(),roughness:.72})
    box(kitchen,.79,.70,.47,x,3.17,-.13,frame,true)
    box(kitchen,.70,.62,.065,x,3.18,.137,doorWood,true)
    box(kitchen,.57,.51,.022,x,3.18,.18,inset)
    box(kitchen,.63,.55,.012,x,3.18,.212,standard(0x9d7d62,{roughness:.80}))
    box(kitchen,.018,.61,.06,x+.335,3.18,.204,standard(0x4a362b,{roughness:.83}))
    if(i<3) box(kitchen,.016,.61,.06,x+.385,3.18,.205,standard(0x3e2c25,{roughness:.86}))
  }
  box(kitchen,3.56,.056,.53,0,3.55,-.11,standard(0x845b43,{map:woodMap(),roughness:.74}),true)
  glowBox(kitchen,3.46,.022,.032,0,2.78,.19,0xffc998)
  for(const x of [-.96,-.32,.30,.94]) glowBox(kitchen,.12,.014,.025,x,2.82,.18,0xffc792)

  // Discrete objects on the counter and open shelves: aligned to real shelf surfaces.
  littlePlant(kitchen,-1.47,1.19,.24,.61)
  clayVase(kitchen,1.39,1.19,.23,0xc1b2a1,.80)
  cylinder(kitchen,.07,.07,.16,-.97,1.28,.25,standard(0x3f5052,{metalness:.24}),24)
  smallBooks(kitchen,-1.22,1.19,.22,.20)
  box(kitchen,.32,.38,.06,-.52,1.40,.26,standard(0xefe7da,{roughness:.95}),true)
  box(kitchen,.24,.30,.03,-.52,1.41,.30,standard(0x8e775d,{roughness:.86}))
  littlePlant(kitchen,-.15,1.20,.24,.48)

  const lowerShelfY = 1.98 + .068/2
  const upperShelfY = 2.28 + .062/2
  shelfBooks(kitchen,-1.14,lowerShelfY,.02,.26,.12)
  clayVase(kitchen,-.34,lowerShelfY,.03,0xd7c4af,.40)
  glowOrb(kitchen,.18,lowerShelfY+.04,.04,.055)
  shelfBooks(kitchen,.90,lowerShelfY,.02,.24,.12)
  clayVase(kitchen,1.36,lowerShelfY,.03,0xa48c78,.42)
  littlePlant(kitchen,1.58,lowerShelfY-.01,.02,.20)

  littlePlant(kitchen,-1.00,upperShelfY-.03,-.02,.22)
  clayVase(kitchen,-.06,upperShelfY-.03,-.01,0xe3d6c4,.30)
  shelfBooks(kitchen,.84,upperShelfY-.02,-.02,.14,.10)
  shelfBooks(kitchen,1.34,upperShelfY-.02,-.02,.12,.09)

  const light=new THREE.PointLight(0xffc596,5.0,3.4,2)
  light.position.set(.12,2.34,.62)
  kitchen.add(light)

  const island=new THREE.Group()
  island.name='KitchenIsland'
  island.position.set(-.53,0,-3.52)
  island.rotation.y=.11
  room.add(island)
  softBox(island,1.53,.09,.60,0,.90,0,stone,.03)
  const dark=standard(0x37302e,{roughness:.65,metalness:.16})
  for(const x of [-.52,.52])for(const z of [-.20,.20])cylinder(island,.036,.036,.82,x,.48,z,dark,9)
}

function makeWallDetails(room) {
  const wood=standard(0x79594c,{roughness:.76})
  const warm=basic(0xffbd85,{toneMapped:false})
  const dark=standard(0x2d272a,{roughness:.88})
  // Left wall focal area and quieter right-side separation of kitchen/window.
  for(const x of [-4.78,-4.48,-4.18])box(room,.10,3.76,.15,x,2.09,-5.22,wood)
  // Rear trim beam and side-wall continuation so the corner lines connect cleanly.
  box(room,10.5,.09,.11,0,3.97,-5.29,wood)
  box(room,.11,.09,10.10,-5.28,3.97,-.32,wood)
  box(room,.11,.09,10.10,5.28,3.97,-.32,wood)
  box(room,10.35,.023,.09,0,3.91,-5.20,warm)
  box(room,.045,.023,10.02,-5.19,3.91,-.32,warm)
  box(room,.045,.023,10.02,5.19,3.91,-.32,warm)
  box(room,10.5,.095,.10,0,.29,-5.28,wood)
  box(room,1.44,1.18,.10,-3.29,2.60,-5.20,wood,true)
  const art=new THREE.Mesh(new THREE.PlaneGeometry(1.25,1),basic(0xffffff,{
    map:pictureMapLandscape(),side:THREE.DoubleSide,toneMapped:false
  }))
  art.position.set(-3.29,2.60,-5.120)
  room.add(art)
  const brass=standard(0x9e8064,{metalness:.42,roughness:.44})
  for(const x of [-2.37,1.31]){
    box(room,.18,.62,.08,x,2.55,-5.10,brass,true)
    box(room,.10,.48,.05,x,2.55,-5.00,dark,true)
    glowBox(room,.055,.34,.032,x,2.55,-4.95,0xffc791)
    box(room,.09,.035,.05,x,2.74,-4.96,brass)
    box(room,.09,.035,.05,x,2.36,-4.96,brass)
    const glow=new THREE.PointLight(0xffbc83,3.7,2.8,2)
    glow.position.set(x,2.55,-4.70)
    room.add(glow)
  }
  box(room,1.34,.07,.31,-3.04,1.57,-5.00,wood)
  cylinder(room,.11,.13,.24,-3.43,1.73,-4.95,standard(0xb4a79a),20)
  for(let i=0;i<3;i++)box(room,.085,.24,.16,-3.12+i*.105,1.72,-4.96,
    standard([0x6b7c79,0x9c7867,0x4b575c][i]))
  plant(room,-4.18,-4.36,.72,.12)
}

function makeSideDetails(room) {
  const oak=standard(0xaf8969,{map:woodMap(),roughness:.76})
  const walnut=standard(0x5f4334,{map:woodMap(),roughness:.80})
  const frameWood=standard(0x7c5a48,{map:woodMap(),roughness:.76})
  const stone=standard(0xe1d3c1,{map:stoneMap(),roughness:.54,metalness:.02})
  const brass=standard(0xaa8b6d,{metalness:.44,roughness:.43})
  const warmLight = standard(0xf3e2c8,{roughness:.92})

  const miniLamp = (x,y,z,scale=.62) => {
    cylinder(room,.07*scale,.07*scale,.11*scale,x,y+.055*scale,z,warmLight,18)
    const glow = new THREE.PointLight(0xffc58a,1.8,1.7,2)
    glow.position.set(x,y+.14*scale,z)
    room.add(glow)
    glowBox(room,.052*scale,.075*scale,.052*scale,x,y+.11*scale,z,0xffcf97)
  }
  const wallShelf = (x,y,z,width) => {
    box(room,.34,.068,width,x,y,z,oak,true)
    glowBox(room,.020,.014,width-.07,x-.18,y-.064,z,0xffc58d)
  }

  // Right wall: fewer overlaps, smaller decor, and a long low console like the reference photo.
  const console = new THREE.Group()
  console.name='RightSideConsole'
  console.position.set(4.93,0,-1.02)
  room.add(console)
  box(console,.50,.68,1.54,0,.36,0,walnut,true)
  box(console,.56,.072,1.62,-.01,.74,0,stone,true)
  for(const z of [-.42,.42]){
    box(console,.020,.55,.04,-.25,.36,z,brass)
    box(console,.020,.55,.04,.25,.36,z,brass)
  }
  for(const z of [-.48,0,.48]) box(console,.42,.46,.018,0,.37,z,standard(0x724d3c,{map:woodMap(),roughness:.86}),true)
  glowBox(console,.018,.015,1.46,0,.036,0,0xffbf83)
  smallBooks(console,-.03,.79,-.32,.22)
  clayVase(console,-.02,.78,.06,0xc8b29f,.56)
  littlePlant(console,-.02,.77,.36,.40)

  wallShelf(4.98,1.56,-1.28,1.12)
  shelfBooks(room,4.90,1.60,-1.02,.22,.10)
  littlePlant(room,5.11,1.58,-1.55,.28)
  miniLamp(5.08,1.56,-1.33,.42)

  wallShelf(4.98,2.22,-0.56,1.00)
  shelfBooks(room,4.95,2.26,-0.80,.24,.10)
  clayVase(room,5.11,2.24,-0.33,0xd0baa5,.48)
  littlePlant(room,4.87,2.24,-0.28,.28)

  // Small framed art (not oversized) tucked between the shelf composition and the window area.
  box(room,.10,.74,.56,5.03,2.08,.44,frameWood,true)
  const rightArt=new THREE.Mesh(new THREE.PlaneGeometry(.42,.60),basic(0xffffff,{
    map:pictureMapLandscape(),toneMapped:false,side:THREE.DoubleSide
  }))
  rightArt.rotation.y=-Math.PI/2
  rightArt.position.set(4.97,2.08,.44)
  room.add(rightArt)

  // Opposite wall: framed art + narrow shelf and low sideboard.
  box(room,.12,1.30,1.25,-5.25,2.60,-1.28,oak,true)
  const leftArt=new THREE.Mesh(new THREE.PlaneGeometry(1.04,1.12),basic(0xffffff,{
    map:pictureMapBotanical(),toneMapped:false,side:THREE.DoubleSide
  }))
  leftArt.rotation.y=Math.PI/2
  leftArt.position.set(-5.165,2.60,-1.28)
  room.add(leftArt)
  box(room,.37,.065,1.21,-5.03,1.35,-2.13,oak,true)
  clayVase(room,-4.93,1.39,-2.37,0xbcb1a1,.61)
  smallBooks(room,-4.89,1.38,-1.97,.27)
  const leftStorage=new THREE.Group()
  leftStorage.position.set(-5.02,0,.80)
  room.add(leftStorage)
  box(leftStorage,.51,.72,1.68,0,.39,0,walnut,true)
  for(const z of [-.42,.42])box(leftStorage,.056,.59,.67,.28,.42,z,oak)
  box(leftStorage,.56,.07,1.78,0,.80,0,oak,true)
  littlePlant(leftStorage,.02,.83,-.55,.59)
  miniLamp(-5.01,.84,.53,.58)

  // Floor plant between the window bench and right-side console, clear of both objects.
  plant(room,4.84,-2.80,.60,-.12)
  plant(room,-4.86,-4.52,.78,.10)
}

// All contact decals use an alpha-faded texture, not real shadow-map geometry.
// This keeps wall cabinets, windows and wall-mounted consoles from throwing
// long rectangular shadows across the foreground when the camera rotates.
let CONTACT_SHADOW_TEXTURE = null
function contactShadowTexture() {
  if (CONTACT_SHADOW_TEXTURE) return CONTACT_SHADOW_TEXTURE
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = 128
  const ctx = canvas.getContext('2d')
  const gradient = ctx.createRadialGradient(64, 64, 8, 64, 64, 63)
  gradient.addColorStop(0, 'rgba(12,13,15,0.62)')
  gradient.addColorStop(0.35, 'rgba(12,13,15,0.34)')
  gradient.addColorStop(0.70, 'rgba(12,13,15,0.11)')
  gradient.addColorStop(1, 'rgba(12,13,15,0)')
  ctx.fillStyle = gradient
  ctx.fillRect(0, 0, 128, 128)
  CONTACT_SHADOW_TEXTURE = new THREE.CanvasTexture(canvas)
  CONTACT_SHADOW_TEXTURE.colorSpace = THREE.SRGBColorSpace
  return CONTACT_SHADOW_TEXTURE
}

function addContactShadow(room, x, z, width, depth, opacity = 0.30) {
  const shadow = new THREE.Mesh(
    new THREE.PlaneGeometry(width, depth),
    new THREE.MeshBasicMaterial({
      map: contactShadowTexture(), color: 0xffffff,
      transparent: true, opacity, depthWrite: false, toneMapped: false,
      polygonOffset: true, polygonOffsetFactor: -1
    })
  )
  shadow.rotation.x = -Math.PI / 2
  shadow.position.set(x, 0.012, z)
  shadow.renderOrder = 1
  shadow.name = 'soft-floor-contact-shadow'
  room.add(shadow)
  return shadow
}

function configureRoomShadows(scene, room) {
  // Leave soft shadows on the sofa, coffee table, island and bench only.
  // Window frames, shelves, wall furniture, ceiling, and large kitchen
  // cabinets should not act like opaque sunlight blockers in an indoor room.
  const keep = new Set(['LeftSofa', 'SofaCoffeeTable', 'KitchenIsland', 'RightWindowBench'])
  let casters = 0, removed = 0
  room.traverse(object => {
    if (!object.isMesh || !object.castShadow) return
    let parent = object.parent
    let eligible = false
    while (parent && parent !== room) {
      if (keep.has(parent.name)) {
        eligible = true
        break
      }
      parent = parent.parent
    }
    if (!eligible) {
      object.castShadow = false
      removed++
    } else {
      casters++
    }
  })

  // A high, near-central key light casts shorter, less directional shadows.
  const key = scene.children.find(object => object.isDirectionalLight && object.castShadow)
  if (key) {
    key.position.set(1.2, 10.0, 5.0)
    key.target.position.set(0, 0.9, -1.0)
    scene.add(key.target)
    key.intensity = Math.min(key.intensity, 2.45)
    key.shadow.mapSize.set(2048, 2048)
    key.shadow.camera.left = -8.5
    key.shadow.camera.right = 8.5
    key.shadow.camera.top = 8.5
    key.shadow.camera.bottom = -8.5
    key.shadow.camera.near = 0.5
    key.shadow.camera.far = 24
    key.shadow.camera.updateProjectionMatrix()
    key.shadow.bias = -0.00018
    key.shadow.normalBias = 0.028
    key.shadow.radius = 3
    key.shadow.needsUpdate = true
  }

  // Small diffuse contact shading anchors furniture even with gentle lighting.
  // Locations are well outside the 3x3 CSI tracking floor (x/z about ±2.2).
  addContactShadow(room, -3.67, -3.54, 2.60, 1.50, 0.22) // sofa/rug
  addContactShadow(room, -3.27, -2.38, 0.88, 0.70, 0.28) // coffee table
  addContactShadow(room, -0.82, -4.95, 3.80, 1.05, 0.30) // cabinets
  addContactShadow(room, -0.53, -3.52, 1.84, 1.06, 0.29) // island
  addContactShadow(room, 3.64, -3.53, 2.18, 0.91, 0.28) // window bench
  addContactShadow(room, 4.93, -1.02, 0.92, 1.70, 0.22) // right console
  addContactShadow(room, -4.85, -3.10, 0.76, 0.75, 0.25) // left cabinet/lamp
  addContactShadow(room, 4.84, -2.80, 0.62, 0.62, 0.18) // right plant
  return {casters, removed}
}

function roomEnvironment(scene) {
  const room = new THREE.Group()
  room.name = 'LivingRoomEnvironment'
  scene.add(room)

  scene.background = new THREE.Color(0x30292b)
  scene.fog = new THREE.Fog(0x30292b, 17, 30)

  for(const x of [-4.2,-1.6,1.2,4.0]){
    const down = new THREE.PointLight(0xffc28a, 1.5, 6.5, 2)
    down.position.set(x,4.02,-1.2)
    scene.add(down)
  }

  flat(room, 11, 11, 0, 0, -0.35,
    standard(0xffffff, { map: floorMap(), roughness: 0.93, metalness: 0.015 }))

  box(room, 11.0, 4.4, 0.12, 0, 2.19, -5.42,
    standard(0xffffff, { map: plasterMap('#4e3a3c', '#3a2b31', '#2e2228'), roughness: 0.99 }))
  box(room, 0.12, 4.4, 11.0, -5.36, 2.19, -0.35,
    standard(0xffffff, { map: plasterMap('#5a483e', '#4d3a3a', '#362d2e'), roughness: 0.99 }))
  box(room, 0.12, 4.4, 11.0, 5.36, 2.19, -0.35,
    standard(0xffffff, { map: plasterMap('#403538', '#372d31', '#2e262c'), roughness: 0.99 }))
  // Ceiling adds real contact and indirect lighting; camera remains underneath.
  box(room, 11,.12,9.8,0,4.42,-.49,standard(0xc1a48b,{roughness:.95}))
  glowBox(room, 10.25,.025,.047,0,4.25,-5.14,0xffc28c)
  glowBox(room,.047,.025,10.10,-5.16,4.25,-.32,0xffc28c)
  glowBox(room,.047,.025,10.10,5.16,4.25,-.32,0xffc28c)
  for(const x of [-2.6,0,2.8]){
    const down=new THREE.PointLight(0xffd0a0,2.2,3.4,2)
    down.position.set(x,4.14,-4.2); room.add(down)
  }
  box(room, 10.8, 0.10, 0.10, 0, 0.13, -5.31, standard(0x8f7064))
  box(room, 0.10, 0.10, 10.6, -5.26, 0.13, -0.35, standard(0x8f7064))
  box(room, 0.10, 0.10, 10.6, 5.26, 0.13, -0.35, standard(0x7f6559))

  makeSofa(room)
  makeKitchen(room)
  makeWallDetails(room)
  makeWindows(room)
  makeSideDetails(room)
  // Soft indirect spill, balanced so cyan tracking tiles stay dominant.
  const accent = new THREE.PointLight(0xffb879,3.7,5.2,2)
  accent.position.set(3.74,1.20,-4.32)
  room.add(accent)
  lamp(room, -4.87, -4.32)
  for (const [x, z, sz, r] of [[-4.46,-4.60,.65,.2],[-4.40,2.75,.58,.9]]) plant(room, x, z, sz, r)
  configureRoomShadows(scene, room)
  return room
}

function labelTexture(n) {
  const c = document.createElement('canvas')
  c.width = 512
  c.height = 256
  const x = c.getContext('2d')
  x.clearRect(0, 0, 512, 256)
  x.textAlign = 'center'
  x.shadowColor = 'rgba(0,12,22,0.80)'
  x.shadowBlur = 12
  x.fillStyle = '#f6ffff'
  x.font = '800 142px Arial, sans-serif'
  x.fillText('P' + String(n).padStart(2, '0'), 256, 145)
  x.fillStyle = '#d3e9f1'
  x.font = '600 49px Arial, sans-serif'
  x.fillText('Zone ' + n, 256, 204)
  const t = new THREE.CanvasTexture(c)
  t.colorSpace = THREE.SRGBColorSpace
  t.anisotropy = 16
  return t
}

function floorZones(scene) {
  const zonePositions = {}
  const tiles = {}
  const zonesRoot = new THREE.Group()
  zonesRoot.name = 'WiSensingTrackingTiles'
  scene.add(zonesRoot)
  const tileBase = standard(MATERIALS.tile, { roughness: 0.78, metalness: 0.21 })
  flat(zonesRoot, 4.74, 4.74, 0, 0.012, 0,
    standard(0x182838, { roughness: 0.8, metalness: 0.15 }))

  for (let row = 0; row < 3; row++) {
    for (let col = 0; col < 3; col++) {
      const n = row * 3 + col + 1
      const xx = (col - 1) * SEPARATOR
      const zz = (row - 1) * SEPARATOR
      const selected = n === 5
      const grp = new THREE.Group()
      grp.position.set(xx, 0, zz)
      zonesRoot.add(grp)
      box(grp, 1.36, 0.020, 1.36, 0, 0.036, 0, tileBase)
      const fillMaterial = basic(MATERIALS.selected, {
        transparent: true, opacity: selected ? 0.22 : 0.012,
        depthWrite: false, toneMapped: false, side: THREE.DoubleSide
      })
      flat(grp, 1.31, 1.31, 0, 0.051, 0, fillMaterial)
      const outer = basic(MATERIALS.accent, {
        transparent: true, opacity: selected ? 0.18 : 0.10,
        depthWrite: false, toneMapped: false
      })
      const border = basic(selected ? MATERIALS.selected : MATERIALS.inactive, { toneMapped: false })
      const corner = basic(selected ? 0xc8ffff : 0x75bfd2, { toneMapped: false })
      const length = 1.36, half = length / 2
      for (const sign of [-1, 1]) {
        box(grp, length, 0.009, 0.085, 0, 0.053, sign * half, outer)
        box(grp, 0.085, 0.009, length, sign * half, 0.053, 0, outer)
        box(grp, length, 0.014, 0.017, 0, 0.067, sign * half, border)
        box(grp, 0.017, 0.014, length, sign * half, 0.067, 0, border)
      }
      for (const sx of [-1, 1]) {
        for (const sz of [-1, 1]) {
          box(grp, 0.19, 0.019, 0.03, sx * 0.587, 0.080, sz * 0.681, corner)
          box(grp, 0.03, 0.019, 0.19, sx * 0.681, 0.080, sz * 0.587, corner)
        }
      }
      const lettering = new THREE.Mesh(
        new THREE.PlaneGeometry(0.96, 0.42),
        basic(0xffffff, {
          map: labelTexture(n), transparent: true, depthWrite: false,
          toneMapped: false, side: THREE.DoubleSide
        })
      )
      lettering.rotation.x = -Math.PI / 2 + 0.84
      lettering.position.set(0, 0.245, 0.36)
      grp.add(lettering)
      lettering.material.opacity = selected ? 1 : 0.87
      const ringMat = basic(0x8ffaff, { transparent: true, opacity: selected ? 0.8 : 0, depthWrite: false, toneMapped: false, side: THREE.DoubleSide })
      const ring = new THREE.Mesh(new THREE.RingGeometry(0.34, 0.356, 56), ringMat)
      ring.rotation.x = -Math.PI / 2
      ring.position.set(0, 0.081, -0.14)
      grp.add(ring)
      tiles[n] = { border, outer, corner, fillMaterial, lettering, ringMat }
      zonePositions[n] = new THREE.Vector3(xx, 0, zz)
    }
  }

  function updateZoneHighlight(zone) {
    for (let n = 1; n <= 9; n++) {
      const item = tiles[n]
      const on = n === zone
      item.border.color.setHex(on ? MATERIALS.selected : MATERIALS.inactive)
      item.corner.color.setHex(on ? 0xc8ffff : 0x75bfd2)
      item.outer.opacity = on ? 0.18 : 0.10
      item.fillMaterial.opacity = on ? 0.22 : 0.012
      item.lettering.material.opacity = on ? 1 : 0.87
      item.ringMat.opacity = on ? 0.8 : 0
    }
  }
  return { zonePositions, updateZoneHighlight }
}

export function createLivingRoomScene(scene) {
  roomEnvironment(scene)
  return floorZones(scene)
}
