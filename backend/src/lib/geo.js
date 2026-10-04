import { config } from '../config.js';

/** Approximate road distance in km between two points. */
export function roadKm(lat1, lng1, lat2, lng2) {
  const R = 6371, r = Math.PI / 180;
  const dLat = (lat2 - lat1) * r, dLng = (lng2 - lng1) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(dLng / 2) ** 2;
  const km = 2 * R * Math.asin(Math.sqrt(h)) * config.roadFactor;
  return Math.max(0.5, Math.round(km * 10) / 10);
}

/** Price breakdown for an order. All amounts in whole TZS. */
export function priceOrder({ pricePerLitre, litres, method, km }) {
  const d = config.delivery[method];
  const fuelCost = Math.round(pricePerLitre * litres);
  const deliveryFee = Math.round((d.baseFee + d.perKm * km) / 50) * 50;
  const serviceFee = Math.round(fuelCost * config.serviceFeeRate);
  return {
    fuelCost, deliveryFee, serviceFee,
    total: fuelCost + deliveryFee + serviceFee,
    riderEarning: Math.round(deliveryFee * config.riderShare),
    etaMinutes: Math.round(12 + (km / d.kmh) * 60),
  };
}
