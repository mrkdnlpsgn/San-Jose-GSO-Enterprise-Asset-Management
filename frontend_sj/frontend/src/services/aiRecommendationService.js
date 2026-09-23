import api from './api';

export const getLatestRecommendation = (assetId) => api.get(`/assets/${assetId}/recommendation`);
export const generateRecommendation  = (assetId) => api.post(`/assets/${assetId}/recommendation`);
export const getRecommendationSummary = () => api.get('/ai-recommendations/summary');

// Maintenance / disposal activity over a period ('day' | 'week' | 'month' | 'year'), scoped to
// the staff member's office; the summary endpoint adds an AI-written paragraph (Gemini).
export const getLifecycleInsights     = (range) => api.get('/ai-insights/lifecycle', { params: { range } });
export const generateLifecycleSummary = (range) => api.post('/ai-insights/lifecycle/summary', null, { params: { range } });
