import { useEffect, useState } from 'react';
import { SafeAreaView } from 'react-native-safe-area-context';
import { H1, T, Button } from '../components/ui';
import { getApiUrl } from '../api';

export default function WrongAppScreen({ user, onSignOut }) {
  const [url, setUrl] = useState('');
  useEffect(() => { getApiUrl().then(setUrl); }, []);
  return (
    <SafeAreaView style={{ flex: 1, padding: 20, gap: 16, justifyContent: 'center' }}>
      <H1>Use the station dashboard</H1>
      <T muted>{user.role === 'admin' ? 'Admin accounts' : 'Fuel station accounts'} are managed on the web dashboard: {url}</T>
      <T muted>This app is for clients ordering fuel and riders delivering it.</T>
      <Button title="Sign out" kind="plain" onPress={onSignOut} />
    </SafeAreaView>
  );
}
