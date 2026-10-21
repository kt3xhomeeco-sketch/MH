'use strict';
class CadViewer {
  constructor(canvas, mark) {
    this.canvas = canvas; this.context = canvas.getContext('2d'); this.mark = mark;
    this.scale = 1; this.offset = [0, 0]; this.key = ''; this.product = null;
    new ResizeObserver(() => this.resize()).observe(canvas);
    canvas.addEventListener('wheel', (event) => {
      event.preventDefault(); const p = this.screen(event); const world = this.world(p);
      this.scale = Math.max(0.0001, Math.min(100, this.scale * Math.exp(-event.deltaY * 0.001)));
      this.offset = [p[0] - world[0] * this.scale, p[1] + world[1] * this.scale]; this.draw();
    }, {passive: false});
    canvas.addEventListener('pointerdown', (event) => { canvas.setPointerCapture(event.pointerId); this.drag = {start: this.screen(event), last: this.screen(event), mark: event.shiftKey}; });
    canvas.addEventListener('pointermove', (event) => {
      if (!this.drag) return; const p = this.screen(event);
      if (!this.drag.mark) { this.offset[0] += p[0] - this.drag.last[0]; this.offset[1] += p[1] - this.drag.last[1]; }
      this.drag.last = p; this.draw();
    });
    canvas.addEventListener('pointerup', () => {
      const drag = this.drag; this.drag = null;
      if (drag?.mark && Math.hypot(drag.start[0] - drag.last[0], drag.start[1] - drag.last[1]) > 8) {
        const a = this.world(drag.start), b = this.world(drag.last);
        this.mark([Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[0], b[0]), Math.max(a[1], b[1])]);
      }
      this.draw();
    });
    canvas.addEventListener('pointercancel', () => { this.drag = null; this.draw(); });
  }
  screen(event) { const rect = this.canvas.getBoundingClientRect(); return [event.clientX - rect.left, event.clientY - rect.top]; }
  world(point) { return [(point[0] - this.offset[0]) / this.scale, (this.offset[1] - point[1]) / this.scale]; }
  project(point) { return [point[0] * this.scale + this.offset[0], -point[1] * this.scale + this.offset[1]]; }
  resize() {
    const rect = this.canvas.getBoundingClientRect(); const ratio = window.devicePixelRatio || 1;
    this.canvas.width = rect.width * ratio; this.canvas.height = rect.height * ratio;
    this.context.setTransform(ratio, 0, 0, ratio, 0, 0); this.draw();
  }
  setProduct(product) {
    this.product = product; const key = product ? `${product.source_hash}:${product.code}:${product.parser_version || ''}:${product.geometry_pipeline?.mode || ''}` : '';
    if (key !== this.key) { this.key = key; this.checkView = false; this.fit(); } else this.draw();
  }
  visibleOutlines() { return (this.checkView ? this.product?.check_outlines : this.product?.outlines) || []; }
  setCheckView(value) { this.checkView = Boolean(value); this.fit(); }
  setEvidence(evidence) {
    this.evidence = new Set((evidence?.handles || []).flatMap((value) => String(value).split('+')));
    this.draw();
  }
  fit() {
    const points = this.visibleOutlines().flatMap((line) => line.points);
    if (!points.length) { this.draw(); return; }
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    points.forEach(([x, y]) => { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); });
    const rect = this.canvas.getBoundingClientRect();
    this.scale = Math.min((rect.width - 32) / Math.max(x1 - x0, 1), (rect.height - 32) / Math.max(y1 - y0, 1));
    this.offset = [rect.width / 2 - (x0 + x1) / 2 * this.scale, rect.height / 2 + (y0 + y1) / 2 * this.scale]; this.draw();
  }
  draw() {
    const c = this.context; const rect = this.canvas.getBoundingClientRect(); c.clearRect(0, 0, rect.width, rect.height);
    c.strokeStyle = '#64748b'; c.lineWidth = 0.75;
    for (const line of this.visibleOutlines()) {
      c.beginPath(); line.points.forEach((point, i) => { const [x, y] = this.project(point); i ? c.lineTo(x, y) : c.moveTo(x, y); }); c.stroke();
    }
    c.strokeStyle = '#e06717'; c.lineWidth = 2;
    for (const line of this.visibleOutlines()) {
      if (!this.evidence?.has(line.handle)) continue;
      c.beginPath(); line.points.forEach((point, i) => { const [x, y] = this.project(point); i ? c.lineTo(x, y) : c.moveTo(x, y); }); c.stroke();
    }
    c.lineWidth = 1.7;
    const proposed = this.product?.status === 'needs_review' ? this.product?.geometry_pipeline?.horizontal?.modules || [] : [];
    const modules = this.checkView ? [] : [...(this.product?.modules || []), ...proposed];
    c.setLineDash(proposed.length ? [6, 4] : []);
    for (const [i, mod] of modules.entries()) {
      if (!mod.source_box) continue;
      const a = this.project(mod.source_box.slice(0, 2)), b = this.project(mod.source_box.slice(2));
      c.strokeStyle = ['#2563eb', '#159578', '#b45309'][i % 3]; c.fillStyle = c.strokeStyle;
      if (mod.plan_profile) {
        const project = p => this.project([mod.source_box[0] + p[0], mod.source_box[1] + p[1]]);
        c.beginPath();
        c.moveTo(...project(mod.plan_profile.segments[0].start));
        for (const segment of mod.plan_profile.segments) {
          if (segment.type === 'arc') {
            const center = project(segment.center);
            const start = Math.atan2(segment.start[1] - segment.center[1], segment.start[0] - segment.center[0]);
            c.arc(...center, segment.radius * this.scale, -start, -(start + segment.sweep), segment.sweep > 0);
          } else c.lineTo(...project(segment.end));
        }
        c.closePath(); c.stroke();
      } else c.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
      c.font = 'bold 12px Segoe UI'; c.fillText(`${proposed.length ? '?' : ''}${mod.id}`, a[0] + 4, b[1] + 15);
    }
    c.setLineDash([]);
    if (!this.checkView && !this.product?.manual_boxes) {
      for (const column of this.product?.geometry_pipeline?.vertical?.columns || []) {
        const a = this.project(column.box.slice(0, 2)), b = this.project(column.box.slice(2));
        c.strokeStyle = '#159578'; c.fillStyle = '#159578';
        c.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]); c.fillText(column.id, a[0] + 4, b[1] + 15);
      }
      for (const box of this.product?.geometry_pipeline?.unassigned_front?.boxes || []) {
        const a = this.project(box.slice(0, 2)), b = this.project(box.slice(2));
        c.strokeStyle = '#dc2626'; c.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
      }
    }
    if (this.drag?.mark) { const a = this.drag.start, b = this.drag.last; c.strokeStyle = '#dc2626'; c.setLineDash([5, 3]); c.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]); c.setLineDash([]); }
    if (!this.product) { c.fillStyle = '#8291a5'; c.font = '13px Segoe UI'; c.fillText('Đọc nguồn CAD để xem sản phẩm.', 20, 32); }
  }
}
if (typeof module !== 'undefined') module.exports = {CadViewer};
