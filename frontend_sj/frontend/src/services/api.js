import axios from 'axios'

const apiBase = import.meta.env.VITE_API_BASE_URL || '/api'
// In prod, the frontend and backend are served from different origins and
// VITE_API_BASE_URL is an absolute URL ending in /api (e.g. http://host:8080/api).
// /uploads lives one level up from /api on that same backend origin, so strip
// the /api suffix to get a prefix for non-API static paths like photo.url.
// In dev, VITE_API_BASE_URL is unset, apiBase is the relative '/api', and this
// resolves to '' — paths stay relative and go through Vite's own proxy.
const backendOrigin = apiBase.replace(/\/api\/?$/, '')

// Resolves a backend-relative path (e.g. "/uploads/maintenance/xxx.jpg") to a URL
// the browser can actually fetch, regardless of whether the frontend and backend
// share an origin.
export function resolveUploadUrl(path) {
  if (!path || /^https?:\/\//i.test(path)) return path
  return `${backendOrigin}${path}`
}

const api = axios.create({
  baseURL: apiBase,
  withCredentials: true, // send HttpOnly JWT cookie automatically
})

// Set by ActionOtpPrompt (mounted in App): asks for the emailed code and repeats the request.
let actionOtpPrompt = null
export const setActionOtpPrompt = (fn) => { actionOtpPrompt = fn }

api.interceptors.response.use(
  (response) => response,
  (error) => {
    // A status change / request decision needs an emailed code: the prompt resolves with the
    // repeated request's response, or rejects (Cancel, or the change itself failed).
    if (error.response?.status === 428 && error.response.data?.code === 'ACTION_OTP_REQUIRED'
        && actionOtpPrompt && !error.config?._otpRetry) {
      return actionOtpPrompt({ info: error.response.data, config: error.config })
    }
    const isAuthRequest = error.config?.url?.includes('/auth/')
    if (error.response?.status === 401 && !isAuthRequest) {
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

// The free Render backend sleeps after ~15 idle minutes and takes up to ~3 minutes to start.
// Meanwhile requests fail with no response, or a 502/503/504 from the Vercel proxy or Render
// (the Vite dev proxy answers 500 with no body). The backend's own errors are always JSON.
export const isServerAsleep = (err) => {
  const res = err?.response
  if (!res) return true
  if ([502, 503, 504].includes(res.status)) return true
  return res.status >= 500 && (typeof res.data !== 'object' || res.data === null)
}

// Resolves once the backend answers at all (a 401 from /auth/me counts — it's awake).
// Calls onWaiting() the first time a check fails. Gives up (rejects) after maxWaitMs.
export async function waitForServer({ onWaiting, maxWaitMs = 5 * 60 * 1000 } = {}) {
  const deadline = Date.now() + maxWaitMs
  let notified = false
  for (;;) {
    try {
      await api.get('/auth/me', { timeout: 20000 })
      return
    } catch (err) {
      if (!isServerAsleep(err)) return
      if (Date.now() > deadline) throw err
      if (!notified) { notified = true; onWaiting?.() }
      await new Promise((r) => setTimeout(r, 4000))
    }
  }
}

export default api
