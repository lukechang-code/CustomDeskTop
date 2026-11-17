const viewport = document.getElementById('viewport');
const workspace = document.getElementById('workspaceContent');

const state = {
  scale: 1,
  offsetX: 0,
  offsetY: 0,
  minScale: 0.7,
  maxScale: 1.7,
  activePointers: new Map(),
  panOrigin: null,
  gestureOrigin: null,
};

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function applyTransform() {
  workspace.style.transform = `translate(${state.offsetX}px, ${state.offsetY}px) scale(${state.scale})`;
}

function getPointerPosition(event) {
  const rect = viewport.getBoundingClientRect();
  return {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  };
}

function getDistance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function getMidpoint(a, b) {
  return {
    x: (a.x + b.x) / 2,
    y: (a.y + b.y) / 2,
  };
}

viewport.addEventListener('pointerdown', (event) => {
  viewport.setPointerCapture(event.pointerId);
  state.activePointers.set(event.pointerId, getPointerPosition(event));

  if (state.activePointers.size === 1) {
    state.panOrigin = {
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      offsetX: state.offsetX,
      offsetY: state.offsetY,
    };
  }

  if (state.activePointers.size === 2) {
    const [first, second] = [...state.activePointers.values()];
    state.gestureOrigin = {
      distance: getDistance(first, second),
      midpoint: getMidpoint(first, second),
      scale: state.scale,
      offsetX: state.offsetX,
      offsetY: state.offsetY,
    };
  }
});

viewport.addEventListener('pointermove', (event) => {
  if (!state.activePointers.has(event.pointerId)) {
    return;
  }

  state.activePointers.set(event.pointerId, getPointerPosition(event));

  if (state.activePointers.size === 1 && state.panOrigin) {
    const dx = event.clientX - state.panOrigin.x;
    const dy = event.clientY - state.panOrigin.y;
    state.offsetX = state.panOrigin.offsetX + dx * 0.9;
    state.offsetY = state.panOrigin.offsetY + dy * 0.9;
    applyTransform();
    return;
  }

  if (state.activePointers.size >= 2 && state.gestureOrigin) {
    const [first, second] = [...state.activePointers.values()];
    const distance = getDistance(first, second);
    const midpoint = getMidpoint(first, second);
    const scaleRatio = distance / state.gestureOrigin.distance;
    state.scale = clamp(state.gestureOrigin.scale * scaleRatio, state.minScale, state.maxScale);

    const dx = midpoint.x - state.gestureOrigin.midpoint.x;
    const dy = midpoint.y - state.gestureOrigin.midpoint.y;
    state.offsetX = state.gestureOrigin.offsetX + dx * 1.1;
    state.offsetY = state.gestureOrigin.offsetY + dy * 1.1;
    applyTransform();
  }
});

viewport.addEventListener('pointerup', (event) => {
  state.activePointers.delete(event.pointerId);

  if (state.activePointers.size === 0) {
    state.panOrigin = null;
    state.gestureOrigin = null;
    return;
  }

  if (state.activePointers.size === 1) {
    const remainingPointer = [...state.activePointers.values()][0];
    state.panOrigin = {
      pointerId: event.pointerId,
      x: remainingPointer.x + viewport.getBoundingClientRect().left,
      y: remainingPointer.y + viewport.getBoundingClientRect().top,
      offsetX: state.offsetX,
      offsetY: state.offsetY,
    };
  }
});

viewport.addEventListener('pointerleave', () => {
  state.activePointers.clear();
  state.panOrigin = null;
  state.gestureOrigin = null;
});

viewport.addEventListener('wheel', (event) => {
  event.preventDefault();
  const factor = event.deltaY > 0 ? 0.92 : 1.08;
  state.scale = clamp(state.scale * factor, state.minScale, state.maxScale);
  applyTransform();
}, { passive: false });

applyTransform();
