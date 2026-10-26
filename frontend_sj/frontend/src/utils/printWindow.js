// Print views open in a window of their own. A window opened with window.open('') shares this
// page's thread, and window.print() holds that thread for as long as the print dialog is open
// (and while Chrome lays out the preview, which takes a while for a long report), so the whole
// system froze until the dialog was closed. Opened with `noopener`, the window gets a thread of
// its own; since it then can't be written to directly, the page is sent over a BroadcastChannel.
//
// Call openPrintWindow() straight from a click (browsers block pop-ups opened later), then
// write(html) now or once the data has loaded; close() takes it away again (e.g. on an error).
export function openPrintWindow({ width = 1100, height = 800, waiting = 'Preparing the report…' } = {}) {
  const channelName = `print-${Date.now()}-${Math.random().toString(36).slice(2)}`
  const page = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${waiting}</title></head>
<body><p style="font:14px Arial,sans-serif;padding:24px">${waiting}</p><script>
  const ch = new BroadcastChannel(${JSON.stringify(channelName)});
  ch.onmessage = (e) => {
    if (e.data === 'close') { ch.close(); window.close(); return }
    if (!e.data || e.data.html == null) return;
    ch.close();
    document.open(); document.write(e.data.html); document.close();
  };
  ch.postMessage('ready');
<\/script></body></html>`
  const url = URL.createObjectURL(new Blob([page], { type: 'text/html' }))
  window.open(url, '_blank', `noopener,width=${width},height=${height}`)

  const channel = new BroadcastChannel(channelName)
  let ready = false
  let pending = null
  const send = (msg) => { channel.postMessage(msg); if (msg === 'close' || msg.html != null) setTimeout(() => channel.close(), 1000) }
  channel.onmessage = (e) => {
    if (e.data !== 'ready') return
    ready = true
    URL.revokeObjectURL(url)
    if (pending) send(pending)
  }
  // a blocked pop-up never says it's ready; let go of everything after a while
  setTimeout(() => { if (!ready) { channel.close(); URL.revokeObjectURL(url) } }, 120000)

  return {
    write(html) { if (ready) send({ html }); else pending = { html } },
    close() { if (ready) send('close'); else pending = 'close' },
  }
}
