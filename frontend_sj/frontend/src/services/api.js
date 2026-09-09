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

api.interceptors.response.use(
  (response) => response,
  (error) => {
    const isAuthRequest = error.config?.url?.includes('/auth/')
    if (error.response?.status === 401 && !isAuthRequest) {
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

export default api
