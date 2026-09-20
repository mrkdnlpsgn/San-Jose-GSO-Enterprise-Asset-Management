import { createSlice } from '@reduxjs/toolkit';

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
});

export const { setAssets, addAsset, updateAsset, removeAsset } = assetSlice.actions;
export default assetSlice.reducer;
