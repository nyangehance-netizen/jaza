import { useEffect, useState } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { api, getToken, setToken, setOnUnauthorized } from './src/api';
import { useTheme } from './src/theme';
import AuthScreen from './src/screens/AuthScreen';
import ClientApp from './src/screens/ClientApp';
import RiderHome from './src/screens/RiderHome';
import WrongAppScreen from './src/screens/WrongAppScreen';

export default function App() {
  const c = useTheme();
  const [user, setUser] = useState(null);
  const [booting, setBooting] = useState(true);

  useEffect(() => {
    setOnUnauthorized(() => setUser(null));
    (async () => {
      try { if (await getToken()) setUser(await api('GET', '/api/me')); } catch {}
      setBooting(false);
    })();
  }, []);

  const signOut = async () => { await setToken(null); setUser(null); };

  let screen;
  if (booting) screen = <View style={{ flex: 1, justifyContent: 'center' }}><ActivityIndicator color={c.brand} size="large" /></View>;
  else if (!user) screen = <AuthScreen onSignedIn={setUser} />;
  else if (user.role === 'client') screen = <ClientApp user={user} onSignOut={signOut} />;
  else if (user.role === 'rider') screen = <RiderHome user={user} onSignOut={signOut} />;
  else screen = <WrongAppScreen user={user} onSignOut={signOut} />;

  return (
    <SafeAreaProvider>
      <StatusBar style="auto" />
      <View style={{ flex: 1, backgroundColor: c.bg }}>{screen}</View>
    </SafeAreaProvider>
  );
}
