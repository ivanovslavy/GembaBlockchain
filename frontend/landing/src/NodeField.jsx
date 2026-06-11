import { useEffect, useRef } from 'react';

// A lightweight 3D node-network rendered to canvas: rotating point cloud (blockchain
// nodes) connected by proximity links, projected with perspective. Indigo→cyan, mouse-
// reactive, theme-agnostic, and disabled for prefers-reduced-motion.
export default function NodeField() {
  const ref = useRef(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    let w = 0, h = 0, dpr = Math.min(window.devicePixelRatio || 1, 2);
    const N = window.innerWidth < 768 ? 46 : 78;
    const R = 240;
    const nodes = [];
    for (let i = 0; i < N; i++) {
      // distribute on a sphere shell (Fibonacci)
      const t = (i + 0.5) / N;
      const phi = Math.acos(1 - 2 * t);
      const theta = Math.PI * (1 + Math.sqrt(5)) * i;
      const rr = R * (0.55 + 0.45 * ((i * 9301 + 49297) % 233280) / 233280);
      nodes.push({
        x: rr * Math.sin(phi) * Math.cos(theta),
        y: rr * Math.sin(phi) * Math.sin(theta),
        z: rr * Math.cos(phi),
        s: 0.6 + ((i * 131) % 100) / 100 * 1.6,
        c: i % 3 === 0 ? '#06B6D4' : (i % 3 === 1 ? '#6366F1' : '#4F46E5'),
      });
    }

    let rotX = -0.3, rotY = 0, targetX = -0.3, targetY = 0, t0 = 0, raf;

    function resize() {
      w = canvas.clientWidth; h = canvas.clientHeight;
      canvas.width = w * dpr; canvas.height = h * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();
    window.addEventListener('resize', resize);

    function onMove(e) {
      const cx = (e.clientX / window.innerWidth - 0.5);
      const cy = (e.clientY / window.innerHeight - 0.5);
      targetY = cx * 0.6; targetX = -0.3 + cy * 0.4;
    }
    window.addEventListener('pointermove', onMove);

    function frame(ts) {
      const dt = t0 ? Math.min((ts - t0) / 1000, 0.05) : 0.016; t0 = ts;
      if (!reduce) rotY += dt * 0.18;
      rotX += (targetX - rotX) * 0.05;
      rotY += (targetY - rotY) * 0.02;

      ctx.clearRect(0, 0, w, h);
      const cx = w / 2, cy = h / 2, focal = 620;
      const sinY = Math.sin(rotY), cosY = Math.cos(rotY), sinX = Math.sin(rotX), cosX = Math.cos(rotX);
      const proj = nodes.map((n) => {
        let x = n.x * cosY - n.z * sinY;
        let z = n.x * sinY + n.z * cosY;
        let y = n.y * cosX - z * sinX;
        z = n.y * sinX + z * cosX;
        const scale = focal / (focal + z + 320);
        return { sx: cx + x * scale, sy: cy + y * scale, scale, z, c: n.c, s: n.s };
      });

      // links between near nodes
      for (let i = 0; i < proj.length; i++) {
        for (let j = i + 1; j < proj.length; j++) {
          const a = proj[i], b = proj[j];
          const dx = a.sx - b.sx, dy = a.sy - b.sy;
          const d2 = dx * dx + dy * dy;
          if (d2 < 11000) {
            const alpha = (1 - d2 / 11000) * 0.22 * Math.min(a.scale, b.scale);
            ctx.strokeStyle = `rgba(99,102,241,${alpha})`;
            ctx.lineWidth = 1;
            ctx.beginPath(); ctx.moveTo(a.sx, a.sy); ctx.lineTo(b.sx, b.sy); ctx.stroke();
          }
        }
      }
      // nodes (painter's order)
      proj.sort((a, b) => a.z - b.z);
      for (const p of proj) {
        const r = p.s * p.scale * 1.7;
        ctx.globalAlpha = Math.max(0.18, Math.min(1, p.scale));
        ctx.fillStyle = p.c;
        ctx.shadowColor = p.c; ctx.shadowBlur = 10 * p.scale;
        ctx.beginPath(); ctx.arc(p.sx, p.sy, r, 0, Math.PI * 2); ctx.fill();
      }
      ctx.globalAlpha = 1; ctx.shadowBlur = 0;
      raf = requestAnimationFrame(frame);
    }
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', resize);
      window.removeEventListener('pointermove', onMove);
    };
  }, []);

  return <canvas ref={ref} style={{ width: '100%', height: '100%', display: 'block' }} aria-hidden="true" />;
}
