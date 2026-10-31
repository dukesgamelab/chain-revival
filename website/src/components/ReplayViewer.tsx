import { useRef, useEffect, useState, useCallback } from 'react'

interface Vec2 { x: number; y: number }

interface MapState {
  id: string
  width: number
  height: number
  blockedTiles: Vec2[]
  tiles: Array<{ x: number; y: number; type: string; blocksLos: boolean; cover: number }>
  victoryPoints: Array<{ x: number; y: number; holder: string }>
}

interface SoldierInit {
  id: number
  teamId: number
  position: Vec2
  facing: Vec2
}

interface InitialState {
  map: MapState
  soldiers: SoldierInit[]
}

interface ReplayEvent {
  t: number
  type: string
  data: Record<string, unknown>
}

interface SoldierState {
  id: number
  teamId: number
  position: Vec2
  facing: Vec2
  isDead: boolean
}

interface Props {
  initialState: InitialState
  events: ReplayEvent[]
  durationMs: number
}

const RENDER_CELL = 18
const VIEW_SIZE = 700
const USA_COLOR = '#38bdf8'
const GER_COLOR = '#f87171'
const VP_COLOR = '#fbbf24'
const MAX_ZOOM = 2.0

function tileColor(type: string, blocksLos: boolean): string {
  const t = type.toLowerCase()
  if (t.includes('tree')) return '#2d5016'
  if (t.includes('bush')) return '#3d6b22'
  if (t.includes('wall') || t.includes('wwal') || t.includes('swal') || t.includes('iwcr')) return '#6b5b3e'
  if (t.includes('window') || t.includes('door')) return '#7a6a4e'
  if (t.includes('bg0') || t.includes('hay')) return '#8b7d3c'
  if (blocksLos) return '#5a4a34'
  return '#4a5568'
}

function buildSoldierStates(initial: SoldierInit[]): SoldierState[] {
  return initial.map(s => ({
    id: s.id,
    teamId: s.teamId,
    position: { ...s.position },
    facing: { ...s.facing },
    isDead: false,
  }))
}

function applySoldierEvent(soldiers: SoldierState[], event: ReplayEvent): void {
  const d = event.data

  switch (event.type) {
    case 'move_result': {
      const moveOrders = (d.moveOrders as Array<Record<string, unknown>>) ?? []
      for (const order of moveOrders) {
        const teamId = Number(order.teamId ?? 0)
        const soldierId = Number(order.soldierId ?? 0)
        const path = (order.path as Vec2[]) ?? []
        const soldier = soldiers.find(s => s.teamId === teamId && s.id === soldierId)
        if (soldier && path.length > 0) {
          soldier.position = { ...path[path.length - 1] }
        }
      }
      const faceUpdates = (d.faceUpdates as Array<Record<string, unknown>>) ?? []
      applyFaceUpdates(soldiers, faceUpdates)
      break
    }
    case 'face_result': {
      const faceUpdates = (d.faceUpdates as Array<Record<string, unknown>>) ?? []
      applyFaceUpdates(soldiers, faceUpdates)
      break
    }
    case 'position_result': {
      const updates = (d.soldierUpdates as Array<Record<string, unknown>>) ?? []
      for (const u of updates) {
        const teamId = Number(u.teamId ?? 0)
        const soldierId = Number(u.soldierId ?? 0)
        const soldier = soldiers.find(s => s.teamId === teamId && s.id === soldierId)
        if (soldier && u.gridPosition) {
          soldier.position = u.gridPosition as Vec2
        }
      }
      break
    }
    case 'combat_shots': {
      const shots = (d.shots as Array<Record<string, unknown>>) ?? []
      for (const shot of shots) {
        if (shot.killed) {
          const tgt = soldiers.find(
            s => s.teamId === Number(shot.targetTeamId) && s.id === Number(shot.targetSoldierId)
          )
          if (tgt) tgt.isDead = true
        }
      }
      break
    }
    case 'grenade_explode': {
      const killed = (d.killed as Array<Record<string, unknown>>) ?? []
      for (const k of killed) {
        const tgt = soldiers.find(
          s => s.teamId === Number(k.teamId) && s.id === Number(k.soldierId)
        )
        if (tgt) tgt.isDead = true
      }
      break
    }
  }
}

function applyFaceUpdates(soldiers: SoldierState[], updates: Array<Record<string, unknown>>): void {
  for (const u of updates) {
    const teamId = Number(u.teamId ?? 0)
    const soldierId = Number(u.soldierId ?? 0)
    const facing = u.facing as Vec2 | undefined
    const soldier = soldiers.find(s => s.teamId === teamId && s.id === soldierId)
    if (soldier && facing) {
      soldier.facing = { ...facing }
    }
  }
}

export function ReplayViewer({ initialState, events, durationMs }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const [eventIndex, setEventIndex] = useState(-1)
  const [playing, setPlaying] = useState(false)
  const [speed, setSpeed] = useState(1)
  const soldiersRef = useRef<SoldierState[]>(buildSoldierStates(initialState.soldiers))
  const playTimerRef = useRef<number | null>(null)

  const { map } = initialState
  const canvasWidth = map.width * RENDER_CELL
  const canvasHeight = map.height * RENDER_CELL

  const fitZoom = Math.min(VIEW_SIZE / canvasWidth, VIEW_SIZE / canvasHeight)
  const [zoom, setZoom] = useState(fitZoom)
  const [pan, setPan] = useState({ x: 0, y: 0 })
  const dragging = useRef(false)
  const lastMouse = useRef({ x: 0, y: 0 })

  const rebuildState = useCallback((toIndex: number) => {
    const soldiers = buildSoldierStates(initialState.soldiers)
    for (let i = 0; i <= toIndex && i < events.length; i++) {
      applySoldierEvent(soldiers, events[i])
    }
    soldiersRef.current = soldiers
  }, [initialState, events])

  const draw = useCallback(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    ctx.clearRect(0, 0, canvasWidth, canvasHeight)

    ctx.fillStyle = '#1a2332'
    ctx.fillRect(0, 0, canvasWidth, canvasHeight)

    ctx.strokeStyle = '#1e293b'
    ctx.lineWidth = 0.5
    for (let x = 0; x <= map.width; x++) {
      ctx.beginPath()
      ctx.moveTo(x * RENDER_CELL, 0)
      ctx.lineTo(x * RENDER_CELL, canvasHeight)
      ctx.stroke()
    }
    for (let y = 0; y <= map.height; y++) {
      ctx.beginPath()
      ctx.moveTo(0, y * RENDER_CELL)
      ctx.lineTo(canvasWidth, y * RENDER_CELL)
      ctx.stroke()
    }

    if (map.tiles && map.tiles.length > 0) {
      for (const tile of map.tiles) {
        ctx.fillStyle = tileColor(tile.type, tile.blocksLos)
        ctx.fillRect(tile.x * RENDER_CELL + 1, tile.y * RENDER_CELL + 1, RENDER_CELL - 2, RENDER_CELL - 2)
      }
    } else {
      for (const cell of map.blockedTiles) {
        ctx.fillStyle = '#3a3a3a'
        ctx.fillRect(cell.x * RENDER_CELL + 1, cell.y * RENDER_CELL + 1, RENDER_CELL - 2, RENDER_CELL - 2)
      }
    }

    for (const vp of map.victoryPoints) {
      const cx = vp.x * RENDER_CELL + RENDER_CELL / 2
      const cy = vp.y * RENDER_CELL + RENDER_CELL / 2
      ctx.fillStyle = VP_COLOR
      ctx.globalAlpha = 0.4
      ctx.beginPath()
      ctx.arc(cx, cy, RENDER_CELL / 2 - 1, 0, Math.PI * 2)
      ctx.fill()
      ctx.globalAlpha = 1
      ctx.strokeStyle = VP_COLOR
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.arc(cx, cy, RENDER_CELL / 2 - 1, 0, Math.PI * 2)
      ctx.stroke()
    }

    const soldiers = soldiersRef.current
    for (const s of soldiers) {
      const cx = s.position.x * RENDER_CELL + RENDER_CELL / 2
      const cy = s.position.y * RENDER_CELL + RENDER_CELL / 2
      const isUsa = s.teamId === 1
      const radius = RENDER_CELL / 2 - 2

      if (s.isDead) {
        ctx.globalAlpha = 0.5
        ctx.beginPath()
        ctx.moveTo(cx - radius, cy - radius)
        ctx.lineTo(cx + radius, cy + radius)
        ctx.moveTo(cx + radius, cy - radius)
        ctx.lineTo(cx - radius, cy + radius)
        ctx.strokeStyle = isUsa ? USA_COLOR : GER_COLOR
        ctx.lineWidth = 2
        ctx.stroke()
        ctx.globalAlpha = 1
      } else {
        ctx.fillStyle = isUsa ? USA_COLOR : GER_COLOR
        ctx.beginPath()
        ctx.arc(cx, cy, radius, 0, Math.PI * 2)
        ctx.fill()

        const fx = cx + s.facing.x * radius * 0.8
        const fy = cy + s.facing.y * radius * 0.8
        ctx.fillStyle = '#ffffff'
        ctx.beginPath()
        ctx.arc(fx, fy, 2, 0, Math.PI * 2)
        ctx.fill()

        ctx.fillStyle = '#000000'
        ctx.font = `bold ${RENDER_CELL * 0.5}px sans-serif`
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.fillText(String(s.id), cx, cy + 1)
      }
    }
  }, [canvasWidth, canvasHeight, map])

  useEffect(() => {
    rebuildState(eventIndex)
    draw()
  }, [eventIndex, rebuildState, draw])

  useEffect(() => {
    if (!playing) {
      if (playTimerRef.current !== null) {
        clearInterval(playTimerRef.current)
        playTimerRef.current = null
      }
      return
    }

    const interval = Math.max(50, 500 / speed)
    playTimerRef.current = window.setInterval(() => {
      setEventIndex(prev => {
        if (prev >= events.length - 1) {
          setPlaying(false)
          return prev
        }
        return prev + 1
      })
    }, interval)

    return () => {
      if (playTimerRef.current !== null) {
        clearInterval(playTimerRef.current)
        playTimerRef.current = null
      }
    }
  }, [playing, speed, events.length])

  const handleWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault()
    const container = containerRef.current
    if (!container) return

    const rect = container.getBoundingClientRect()
    const mouseX = e.clientX - rect.left
    const mouseY = e.clientY - rect.top

    const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15
    setZoom(prev => {
      const next = Math.min(MAX_ZOOM, Math.max(fitZoom, prev * factor))
      const scale = next / prev
      setPan(p => ({
        x: mouseX - scale * (mouseX - p.x),
        y: mouseY - scale * (mouseY - p.y),
      }))
      return next
    })
  }, [fitZoom])

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (e.button !== 0) return
    dragging.current = true
    lastMouse.current = { x: e.clientX, y: e.clientY }
  }, [])

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (!dragging.current) return
    const dx = e.clientX - lastMouse.current.x
    const dy = e.clientY - lastMouse.current.y
    lastMouse.current = { x: e.clientX, y: e.clientY }
    setPan(p => ({ x: p.x + dx, y: p.y + dy }))
  }, [])

  const handleMouseUp = useCallback(() => {
    dragging.current = false
  }, [])

  const resetView = useCallback(() => {
    setZoom(fitZoom)
    setPan({ x: 0, y: 0 })
  }, [fitZoom])

  const currentTime = eventIndex >= 0 && eventIndex < events.length
    ? events[eventIndex].t
    : 0

  return (
    <div>
      {/* Canvas with zoom/pan */}
      <div
        ref={containerRef}
        className="mx-auto mb-2 border border-slate-700 rounded cursor-grab active:cursor-grabbing select-none"
        style={{ width: VIEW_SIZE, height: VIEW_SIZE, overflow: 'hidden', position: 'relative' }}
        onWheel={handleWheel}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
      >
        <canvas
          ref={canvasRef}
          width={canvasWidth}
          height={canvasHeight}
          style={{
            imageRendering: 'pixelated',
            transformOrigin: '0 0',
            transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
          }}
        />
      </div>

      {/* Zoom controls + legend */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <button
            onClick={resetView}
            className="px-2 py-1 bg-slate-700 hover:bg-slate-600 rounded text-xs transition-colors"
          >
            Fit
          </button>
          <span className="text-xs text-slate-500">{Math.round(zoom * 100)}%</span>
          <span className="text-xs text-slate-600">Scroll to zoom, drag to pan</span>
        </div>
        <div className="flex items-center gap-4 text-xs text-slate-400">
          <span className="flex items-center gap-1">
            <span className="inline-block w-3 h-3 rounded-full" style={{ background: USA_COLOR }} />
            USA
          </span>
          <span className="flex items-center gap-1">
            <span className="inline-block w-3 h-3 rounded-full" style={{ background: GER_COLOR }} />
            Germany
          </span>
          <span className="flex items-center gap-1">
            <span className="inline-block w-3 h-3 rounded-full border-2" style={{ borderColor: VP_COLOR, background: 'transparent' }} />
            VP
          </span>
        </div>
      </div>

      {/* Progress bar */}
      <div className="mb-3">
        <input
          type="range"
          min={-1}
          max={events.length - 1}
          value={eventIndex}
          onChange={e => { setPlaying(false); setEventIndex(Number(e.target.value)) }}
          className="w-full h-1.5 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-sky-500"
        />
      </div>

      {/* Controls */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <button
            onClick={() => { setPlaying(false); setEventIndex(-1) }}
            className="px-2 py-1 bg-slate-700 hover:bg-slate-600 rounded text-sm transition-colors"
            title="Reset"
          >
            {'|<'}
          </button>
          <button
            onClick={() => { setPlaying(false); setEventIndex(prev => Math.max(-1, prev - 1)) }}
            className="px-2 py-1 bg-slate-700 hover:bg-slate-600 rounded text-sm transition-colors"
          >
            {'<'}
          </button>
          <button
            onClick={() => setPlaying(!playing)}
            className="px-4 py-1 bg-sky-600 hover:bg-sky-500 rounded text-sm font-medium transition-colors min-w-[60px]"
          >
            {playing ? 'Pause' : 'Play'}
          </button>
          <button
            onClick={() => { setPlaying(false); setEventIndex(prev => Math.min(events.length - 1, prev + 1)) }}
            className="px-2 py-1 bg-slate-700 hover:bg-slate-600 rounded text-sm transition-colors"
          >
            {'>'}
          </button>
          <button
            onClick={() => { setPlaying(false); setEventIndex(events.length - 1) }}
            className="px-2 py-1 bg-slate-700 hover:bg-slate-600 rounded text-sm transition-colors"
            title="End"
          >
            {'>|'}
          </button>
        </div>

        <div className="flex items-center gap-3 text-sm text-slate-400">
          <span className="font-mono">{formatMs(currentTime)} / {formatMs(durationMs)}</span>
          <span className="text-slate-600">|</span>
          <span>Event {Math.max(0, eventIndex + 1)}/{events.length}</span>
          <span className="text-slate-600">|</span>
          <div className="flex items-center gap-1">
            {[1, 2, 4].map(s => (
              <button
                key={s}
                onClick={() => setSpeed(s)}
                className={`px-1.5 py-0.5 rounded text-xs transition-colors ${
                  speed === s ? 'bg-sky-600 text-white' : 'bg-slate-700 hover:bg-slate-600 text-slate-400'
                }`}
              >
                {s}x
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

function formatMs(ms: number): string {
  const totalSec = Math.floor(ms / 1000)
  const m = Math.floor(totalSec / 60)
  const s = totalSec % 60
  return `${m}:${s.toString().padStart(2, '0')}`
}
