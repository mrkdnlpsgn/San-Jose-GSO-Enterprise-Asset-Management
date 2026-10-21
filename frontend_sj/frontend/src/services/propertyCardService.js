import api from './api';

// Property Cards exist only for assets that have been transferred at least once.
export const getPropertyCards = ()        => api.get('/property-cards');
export const getPropertyCard  = (assetId) => api.get(`/property-cards/${assetId}`);
