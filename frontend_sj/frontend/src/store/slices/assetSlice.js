import { createSlice } from '@reduxjs/toolkit';
import { setCredentials, logout } from './authSlice';

const assetSlice = createSlice({
  name: 'assets',
  initialState: { items: [] },
  reducers: {
    setAssets: (state, action) => { state.items = action.payload; },
    // Both the direct create-response handler and the SSE 'asset' CREATED
    // event can dispatch this for the same asset (the SSE emit fires
    // server-side before the HTTP response returns) — guard against
    // inserting it twice.
    addAsset: (state, action) => {
      if (state.items.some((i) => i.id === action.payload.id)) return;
      state.items.unshift(action.payload);
    },
    updateAsset: (state, action) => {
      const idx = state.items.findIndex(i => i.id === action.payload.id);
      if (idx !== -1) state.items[idx] = action.payload;
    },
    removeAsset: (state, action) => {
      state.items = state.items.filter(i => i.id !== action.payload);
    },
  },
  // The cached list belongs to whoever loaded it — staff only get their office's assets —
  // so drop it whenever the signed-in account changes or signs out.
  extraReducers: (builder) => {
    builder
      .addCase(logout, (state) => { state.items = []; })
      .addCase(setCredentials, (state) => { state.items = []; });
  },
});

export const { setAssets, addAsset, updateAsset, removeAsset } = assetSlice.actions;
export default assetSlice.reducer;
