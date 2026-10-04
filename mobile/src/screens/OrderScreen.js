import { useEffect, useMemo, useState } from 'react';
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, View } from 'react-native';
import * as Location from 'expo-location';
import { api, tzs, phoneFmt } from '../api';
import { useTheme } from '../theme';
import { H1, H2, T, Card, Button, Field, Choice, Line, ErrorText, Row } from '../components/ui';

// Used when the phone cannot share its location.
const AREAS = [
  ['Mikocheni', -6.765, 39.248], ['Masaki', -6.75, 39.283], ['Kariakoo', -6.818, 39.274], ['Sinza', -6.778, 39.219],
  ['Mbezi Beach', -6.721, 39.222], ['Ubungo', -6.792, 39.214], ['Kigamboni', -6.843, 39.318], ['Tegeta', -6.69, 39.212],
  ['Kinondoni', -6.776, 39.257], ['Temeke', -6.866, 39.257], ['Ilala', -6.827, 39.255], ['Mbagala', -6.9, 39.27],
];
const VEHICLES = ['Car', 'SUV / Pickup', 'Motorcycle', 'Bajaji', 'Truck / Bus'];
const QUICK = [5, 10, 20, 50, 100];

export default function OrderScreen({ user, onPlaced }) {
  const c = useTheme();
  const [cfg, setCfg] = useState(null);
  const [loc, setLoc] = useState(null); // { lat, lng, accuracy, source }
  const [locMsg, setLocMsg] = useState('Finding your location…');
  const [landmark, setLandmark] = useState('');
  const [plate, setPlate] = useState('');
  const [vehicle, setVehicle] = useState('Car');
  const [fuel, setFuel] = useState('petrol');
  const [litres, setLitres] = useState(10);
  const [delivery, setDelivery] = useState('boda');
  const [nearby, setNearby] = useState(null);
  const [stationId, setStationId] = useState(null);
  const [pay, setPay] = useState(null);
  const [payPhone, setPayPhone] = useState(phoneFmt(user.phone));
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => { api('GET', '/api/config').then(setCfg).catch((e) => setErr(e.message)); locate(); }, []);

  async function locate() {
    setLocMsg('Finding your location…');
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') { setLocMsg('Location is off. Pick your area below.'); return; }
      const p = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
      setLoc({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy, source: 'gps' });
      setLocMsg('');
    } catch { setLocMsg('Could not read your location. Pick your area below.'); }
  }

  // Keep litres inside the chosen delivery method's limits.
  const limits = cfg?.delivery?.[delivery];
  useEffect(() => {
    if (!cfg) return;
    if (litres > cfg.delivery.boda.maxLitres && delivery === 'boda') setDelivery('tanker');
    if (litres < cfg.delivery.tanker.minLitres && delivery === 'tanker') setDelivery('boda');
  }, [litres, cfg]);

  // Fetch stations whenever the request changes (debounced).
  useEffect(() => {
    if (!loc || !limits || litres < limits.minLitres || litres > limits.maxLitres) { setNearby(null); return; }
    const t = setTimeout(async () => {
      try {
        const r = await api('GET', `/api/stations/nearby?lat=${loc.lat}&lng=${loc.lng}&fuel=${fuel}&litres=${litres}&delivery=${delivery}`);
        setNearby(r.stations);
        const firstOk = r.stations.find((s) => s.available);
        setStationId((cur) => (r.stations.find((s) => s.station_id === cur && s.available) ? cur : firstOk?.station_id ?? null));
      } catch (e) { setErr(e.message); }
    }, 350);
    return () => clearTimeout(t);
  }, [loc, fuel, litres, delivery, limits]);

  const station = useMemo(() => nearby?.find((s) => s.station_id === stationId), [nearby, stationId]);
  useEffect(() => {
    if (station && !station.payment_methods.find((m) => m.method === pay)) setPay(station.payment_methods[0]?.method ?? null);
  }, [station]);
  const payKind = station?.payment_methods.find((m) => m.method === pay)?.kind;

  async function place() {
    setErr('');
    if (!plate.trim()) return setErr('Add your plate number so the rider finds the right vehicle.');
    setBusy(true);
    try {
      const r = await api('POST', '/api/orders', {
        station_id: station.station_id, product_id: station.product_id, litres, delivery_method: delivery,
        lat: loc.lat, lng: loc.lng, landmark, plate, vehicle_type: vehicle, payment_method: pay,
        payment_phone: payKind === 'mobile' ? payPhone : undefined,
      });
      onPlaced(r.order, r.payment);
    } catch (e) { setErr(e.message); }
    setBusy(false);
  }

  const stepLitres = (d) => setLitres((l) => Math.min(1000, Math.max(1, l + d)));

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={{ padding: 16, gap: 14, paddingBottom: 32 }} keyboardShouldPersistTaps="handled">
        <H1>Order fuel</H1>

        <Card>
          <H2>Where are you?</H2>
          {loc?.source === 'gps' ? (
            <Row style={{ justifyContent: 'space-between' }}>
              <T muted small>Using your location (within {Math.round(loc.accuracy || 0)} m)</T>
              <Pressable onPress={locate}><T small style={{ color: c.brand, fontWeight: '700' }}>Refresh</T></Pressable>
            </Row>
          ) : (
            <>
              <T muted small>{locMsg}</T>
              <Choice wrap value={loc?.source} onChange={(v) => { const a = AREAS.find((x) => x[0] === v); setLoc({ lat: a[1], lng: a[2], source: a[0] }); }}
                options={AREAS.map(([n]) => ({ value: n, label: n }))} />
              {!locMsg.startsWith('Finding') && <Button title="Try my location again" kind="plain" onPress={locate} />}
            </>
          )}
          <Field label="Landmark or street" value={landmark} onChangeText={setLandmark} placeholder="e.g. opposite Shoppers Plaza" />
        </Card>

        <Card>
          <H2>Your vehicle</H2>
          <Field label="Plate number" value={plate} onChangeText={setPlate} autoCapitalize="characters" placeholder="T 482 DKP" />
          <Choice wrap value={vehicle} onChange={setVehicle} options={VEHICLES.map((v) => ({ value: v, label: v }))} />
        </Card>

        <Card>
          <H2>Fuel</H2>
          <Choice wrap value={fuel} onChange={setFuel} options={[{ value: 'petrol', label: 'Petrol' }, { value: 'diesel', label: 'Diesel' }]} />
          <Row style={{ justifyContent: 'space-between' }}>
            <Pressable onPress={() => stepLitres(-5)} style={{ padding: 10 }} accessibilityLabel="Less fuel"><Text style={{ fontSize: 28, color: c.ink }}>−</Text></Pressable>
            <Text style={{ fontSize: 40, fontWeight: '800', color: c.ink, fontVariant: ['tabular-nums'] }}>{litres}<Text style={{ fontSize: 18, color: c.muted }}> L</Text></Text>
            <Pressable onPress={() => stepLitres(5)} style={{ padding: 10 }} accessibilityLabel="More fuel"><Text style={{ fontSize: 28, color: c.ink }}>+</Text></Pressable>
          </Row>
          <Row>{QUICK.map((q) => (
            <Pressable key={q} onPress={() => setLitres(q)} style={{ paddingHorizontal: 14, paddingVertical: 8, borderRadius: 999, borderWidth: 1, borderColor: litres === q ? c.brand : c.line, backgroundColor: litres === q ? c.brandSoft : c.surface }}>
              <Text style={{ color: c.ink, fontWeight: '700' }}>{q} L</Text>
            </Pressable>))}
          </Row>
        </Card>

        {cfg && (
          <Card>
            <H2>How it reaches you</H2>
            <Choice value={delivery} onChange={setDelivery} options={Object.entries(cfg.delivery).map(([k, d]) => ({
              value: k, label: d.label, right: `from ${tzs(d.baseFee)}`,
              sub: `${d.minLitres}–${d.maxLitres} L${k === 'boda' ? ' in sealed jerrycans' : ', metered pump'}`,
              disabled: litres < d.minLitres || litres > d.maxLitres,
            }))} />
          </Card>
        )}

        <Card>
          <H2>Choose a station</H2>
          {!loc ? <T muted>Set your location first.</T>
            : !nearby ? <T muted>Looking for stations…</T>
            : !nearby.length ? <T muted>No station sells this fuel near you yet.</T>
            : <Choice value={stationId} onChange={setStationId} options={nearby.map((s) => ({
                value: s.station_id, label: s.name, right: `${s.price_per_litre.toLocaleString()}/L`, disabled: !s.available,
                sub: `${s.distance_km} km · ${s.available ? `about ${s.quote.etaMinutes} min` : s.unavailable_reason}`,
              }))} />}
        </Card>

        {station && (
          <Card>
            <H2>Pay with</H2>
            <Choice wrap value={pay} onChange={setPay} options={station.payment_methods.map((m) => ({ value: m.method, label: m.label }))} />
            {payKind === 'mobile' && <Field label="Mobile money number" value={payPhone} onChangeText={setPayPhone} keyboardType="phone-pad" />}
            {payKind === 'bank' && <T muted small>You get the station's account after ordering. The station starts once it confirms your transfer.</T>}
          </Card>
        )}

        {station && (
          <Card highlight>
            <Line left={`Fuel  ${litres} L × ${station.price_per_litre.toLocaleString()}`} right={tzs(station.quote.fuelCost)} />
            <Line left={`Delivery  ${station.distance_km} km`} right={tzs(station.quote.deliveryFee)} />
            <Line left="Service fee" right={tzs(station.quote.serviceFee)} />
            <View style={{ borderTopWidth: 1, borderColor: c.line, borderStyle: 'dashed', paddingTop: 10 }}>
              <Line strong left="Total" right={tzs(station.quote.total)} />
            </View>
            <ErrorText>{err}</ErrorText>
            <Button title="Request fuel" onPress={place} loading={busy} disabled={!pay} />
          </Card>
        )}
        {!station && <ErrorText>{err}</ErrorText>}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
