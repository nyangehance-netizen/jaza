import { useEffect, useState } from 'react';
import { FlatList, Pressable, View } from 'react-native';
import { api, tzs, phoneFmt } from '../api';
import { useTheme } from '../theme';
import { H1, T, Card, Pill, Button, Row } from '../components/ui';

export default function HistoryScreen({ user, onOpen, onSignOut }) {
  const c = useTheme();
  const [orders, setOrders] = useState(null);
  const [loading, setLoading] = useState(false);
  const load = async () => { setLoading(true); try { setOrders(await api('GET', '/api/orders')); } catch {} setLoading(false); };
  useEffect(() => { load(); }, []);

  return (
    <FlatList
      contentContainerStyle={{ padding: 16, gap: 10 }}
      data={orders || []}
      keyExtractor={(o) => String(o.id)}
      refreshing={loading}
      onRefresh={load}
      ListHeaderComponent={<View style={{ gap: 4, marginBottom: 6 }}><H1>My orders</H1><T muted small>{user.name} · {phoneFmt(user.phone)}</T></View>}
      ListEmptyComponent={<T muted>{orders ? 'Your fuel orders will show here.' : 'Loading…'}</T>}
      renderItem={({ item: o }) => (
        <Pressable onPress={() => onOpen(o.id)}>
          <Card style={{ gap: 6 }}>
            <Row style={{ justifyContent: 'space-between' }}>
              <T bold>{o.litres} L {o.product_name}</T>
              <Pill text={o.status_label} tone={o.status === 'delivered' ? 'ok' : ['cancelled', 'rejected'].includes(o.status) ? 'bad' : 'brand'} />
            </Row>
            <T muted small>{o.code} · {o.station.name} · {o.created_at.slice(0, 16)}</T>
            <T bold style={{ fontVariant: ['tabular-nums'] }}>{tzs(o.total)}</T>
          </Card>
        </Pressable>
      )}
      ListFooterComponent={<Button title="Sign out" kind="plain" onPress={onSignOut} style={{ marginTop: 16 }} />}
    />
  );
}
