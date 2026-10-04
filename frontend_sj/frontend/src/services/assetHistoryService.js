import api from './api';

export const getAssetHistory    = (search = '') => search.trim()
  ? api.get('/asset-history', { params: { search: search.trim() } })
  : api.get('/asset-history');
// Asset History page — admin: everything; staff: every event on the assets they're the
// accountable person for.
export const getAccountableHistory = (search = '') => search.trim()
  ? api.get('/asset-history/accountable', { params: { search: search.trim() } })
  : api.get('/asset-history/accountable');
export const getHistoryByAsset  = (id)    => api.get(`/asset-history/asset/${id}`);
// Staff maintenance/disposal requests and their outcome. Admin: userId narrows to one
// person (omit for everyone). Staff: the backend always returns only their own.
export const getEditRequests    = (userId) => api.get('/asset-history/requests', { params: userId ? { userId } : {} });
