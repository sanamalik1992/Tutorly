import { useEffect, useRef, useImperativeHandle, forwardRef, useState } from 'react'

export const Whiteboard = forwardRef(function Whiteboard({ tool, color, size }, ref) {
  const canvasRef = useRef(null)
  const wrapRef = useRef(null)
  const drawingRef = useRef(false)
  const lastRef = useRef({ x: 0, y: 0 })
  const ctxRef = useRef(null)
  const scaleRef = useRef({ x: 1, y: 1 })
  const [dims, setDims] = useState({ w: 900, h: 600 })

  // Logical canvas dimensions (what the AI targets)
  const LOGICAL_W = 900
  const LOGICAL_H = 600

  useEffect(() => {
    const resize = () => {
      const wrap = wrapRef.current
      if (!wrap) return
      const rect = wrap.getBoundingClientRect()
      const w = Math.floor(rect.width)
      const h = Math.floor(rect.height)
      setDims({ w, h })
      const canvas = canvasRef.current
      if (!canvas) return
      const dpr = window.devicePixelRatio || 1
      canvas.width = w * dpr
      canvas.height = h * dpr
      canvas.style.width = w + 'px'
      canvas.style.height = h + 'px'
      const ctx = canvas.getContext('2d')
      ctx.scale(dpr, dpr)
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctxRef.current = ctx
      scaleRef.current = { x: w / LOGICAL_W, y: h / LOGICAL_H }
    }
    resize()
    window.addEventListener('resize', resize)
    return () => window.removeEventListener('resize', resize)
  }, [])

  const pos = (e) => {
    const rect = canvasRef.current.getBoundingClientRect()
    const clientX = e.touches ? e.touches[0].clientX : e.clientX
    const clientY = e.touches ? e.touches[0].clientY : e.clientY
    return { x: clientX - rect.left, y: clientY - rect.top }
  }

  const startDraw = (e) => {
    e.preventDefault()
    drawingRef.current = true
    lastRef.current = pos(e)
  }

  const moveDraw = (e) => {
    if (!drawingRef.current) return
    e.preventDefault()
    const ctx = ctxRef.current
    const p = pos(e)
    ctx.strokeStyle = tool === 'eraser' ? '#ffffff' : color
    ctx.lineWidth = tool === 'eraser' ? size * 4 : size
    ctx.globalCompositeOperation = tool === 'eraser' ? 'destination-out' : 'source-over'
    ctx.beginPath()
    ctx.moveTo(lastRef.current.x, lastRef.current.y)
    ctx.lineTo(p.x, p.y)
    ctx.stroke()
    lastRef.current = p
  }

  const endDraw = () => { drawingRef.current = false }

  // AI drawing commands
  const runCommands = (commands, clear = false) => {
    const ctx = ctxRef.current
    if (!ctx) return
    const { x: sx, y: sy } = scaleRef.current

    if (clear) {
      ctx.save()
      ctx.setTransform(1, 0, 0, 1, 0, 0)
      ctx.clearRect(0, 0, canvasRef.current.width, canvasRef.current.height)
      ctx.restore()
      const dpr = window.devicePixelRatio || 1
      ctx.scale(dpr, dpr)
    }

    ctx.globalCompositeOperation = 'source-over'

    const animateDelay = 300 // ms between commands for nice effect
    commands.forEach((cmd, i) => {
      setTimeout(() => drawCommand(ctx, cmd, sx, sy), i * animateDelay)
    })
  }

  const drawCommand = (ctx, cmd, sx, sy) => {
    ctx.save()
    const c = cmd.color || '#0f1a2e'
    ctx.strokeStyle = c
    ctx.fillStyle = c
    ctx.lineWidth = (cmd.width || 2)

    switch (cmd.type) {
      case 'text': {
        const size = cmd.size || 28
        ctx.font = `${size}px "Fraunces", Georgia, serif`
        ctx.textBaseline = 'alphabetic'
        ctx.fillText(cmd.text || '', cmd.x * sx, cmd.y * sy)
        break
      }
      case 'line': {
        ctx.beginPath()
        ctx.moveTo(cmd.x1 * sx, cmd.y1 * sy)
        ctx.lineTo(cmd.x2 * sx, cmd.y2 * sy)
        ctx.stroke()
        break
      }
      case 'arrow': {
        const x1 = cmd.x1 * sx, y1 = cmd.y1 * sy
        const x2 = cmd.x2 * sx, y2 = cmd.y2 * sy
        ctx.beginPath()
        ctx.moveTo(x1, y1)
        ctx.lineTo(x2, y2)
        ctx.stroke()
        const angle = Math.atan2(y2 - y1, x2 - x1)
        const head = 12
        ctx.beginPath()
        ctx.moveTo(x2, y2)
        ctx.lineTo(x2 - head * Math.cos(angle - Math.PI / 6), y2 - head * Math.sin(angle - Math.PI / 6))
        ctx.lineTo(x2 - head * Math.cos(angle + Math.PI / 6), y2 - head * Math.sin(angle + Math.PI / 6))
        ctx.closePath()
        ctx.fill()
        break
      }
      case 'circle': {
        ctx.beginPath()
        ctx.arc(cmd.cx * sx, cmd.cy * sy, (cmd.r || 20) * Math.min(sx, sy), 0, Math.PI * 2)
        if (cmd.fill) ctx.fill()
        else ctx.stroke()
        break
      }
      case 'rect': {
        if (cmd.fill) ctx.fillRect(cmd.x * sx, cmd.y * sy, (cmd.w || 50) * sx, (cmd.h || 50) * sy)
        else ctx.strokeRect(cmd.x * sx, cmd.y * sy, (cmd.w || 50) * sx, (cmd.h || 50) * sy)
        break
      }
      case 'path': {
        // free-form path: cmd.points = [[x,y], ...]
        if (!cmd.points?.length) break
        ctx.beginPath()
        ctx.moveTo(cmd.points[0][0] * sx, cmd.points[0][1] * sy)
        for (let i = 1; i < cmd.points.length; i++) {
          ctx.lineTo(cmd.points[i][0] * sx, cmd.points[i][1] * sy)
        }
        ctx.stroke()
        break
      }
      default:
        break
    }
    ctx.restore()
  }

  const clearAll = () => {
    const ctx = ctxRef.current
    const canvas = canvasRef.current
    if (!ctx || !canvas) return
    ctx.save()
    ctx.setTransform(1, 0, 0, 1, 0, 0)
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    ctx.restore()
    const dpr = window.devicePixelRatio || 1
    ctx.scale(dpr, dpr)
  }

  const exportImage = () => {
    const canvas = canvasRef.current
    if (!canvas) return null
    // Composite with cream paper background so the PNG isn't transparent
    const out = document.createElement('canvas')
    out.width = canvas.width
    out.height = canvas.height
    const octx = out.getContext('2d')
    octx.fillStyle = '#fffdf8'
    octx.fillRect(0, 0, out.width, out.height)
    octx.drawImage(canvas, 0, 0)
    return out.toDataURL('image/png')
  }

  useImperativeHandle(ref, () => ({ runCommands, clearAll, exportImage }), [])

  return (
    <div className="board-wrap" ref={wrapRef}>
      <canvas
        ref={canvasRef}
        onMouseDown={startDraw}
        onMouseMove={moveDraw}
        onMouseUp={endDraw}
        onMouseLeave={endDraw}
        onTouchStart={startDraw}
        onTouchMove={moveDraw}
        onTouchEnd={endDraw}
      />
    </div>
  )
})
