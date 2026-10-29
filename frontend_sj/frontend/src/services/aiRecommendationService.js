import api from './api';

export const getLatestRecommendation = (assetId) => api.get(`/assets/${assetId}/recommendation`);
export const generateRecommendation  = (assetId) => api.post(`/assets/${assetId}/recommendation`);
export const getRecommendationSummary = () => api.get('/ai-recommendations/summary');

// Reports: assets due for replacement now and in each of the next `years` years, with the
// estimated cost (priceIncrease = percent per year); items = true adds the asset list.
export const getReplacementForecast = (params = {}) =>
  api.get('/ai-insights/replacement-forecast', { params });

// Reports: straight-line depreciation schedule as of a date (default today), same formulas as
// the Accounting Office's printed schedule; items = true adds the asset rows.
export const getDepreciation = (params = {}) =>
  api.get('/ai-insights/depreciation', { params });

// Reports: repair and maintenance cost per year (last 3 full years and this year so far) by
// category, and the estimate for next year.
export const getMaintenanceForecast = (params = {}) =>
  api.get('/ai-insights/maintenance-forecast', { params });

// Home "Budget & Planning" (admins only): replacement forecast + depreciation totals, with one AI
// summary covering both. Cached on the server while the numbers are unchanged.
export const getPlanning = () => api.get('/ai-insights/planning');
export const generatePlanningSummary = (refresh = false) =>
  api.post('/ai-insights/planning/summary', null, { params: { refresh } });
