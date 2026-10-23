import api from './api';

// The dashboard's asset numbers, worked out by the server (in use, value, condition, offices,
// categories, and what needs attention) - a small response instead of every asset and record.
export const getDashboardSummary = () => api.get('/dashboard/summary');
