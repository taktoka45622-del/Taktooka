export function createPageLoader(document) {
  const loaded = new WeakSet();
  const pending = new WeakMap();
  return function load(node, request) {
    if (!node) return Promise.resolve().then(request);
    if (pending.has(node)) return pending.get(node);
    let skeleton;
    const initial = !loaded.has(node);
    if (initial) {
      node.dataset.initialLoading = 'true';
      node.setAttribute('aria-busy', 'true');
      skeleton = document.createElement('div');
      skeleton.className = 'tkt-skeleton';
      skeleton.setAttribute('role', 'status');
      skeleton.setAttribute('aria-label', 'جاري التحميل');
      for (let i = 0; i < 5; i++) {
        const card = document.createElement('div');
        card.className = 'tkt-skeleton-card';
        const image = document.createElement('span');
        image.className = 'tkt-skeleton-image';
        const lines = document.createElement('div');
        for (let j = 0; j < 3; j++) lines.append(document.createElement('span'));
        card.append(image, lines);
        skeleton.append(card);
      }
      node.append(skeleton);
    }
    const task = Promise.resolve().then(request).then(value => {
      loaded.add(node);
      return value;
    }).finally(() => {
      pending.delete(node);
      if (initial) {
        skeleton.remove();
        delete node.dataset.initialLoading;
        node.removeAttribute('aria-busy');
      }
    });
    pending.set(node, task);
    return task;
  };
}
