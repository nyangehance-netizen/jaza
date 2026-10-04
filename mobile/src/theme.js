import { useColorScheme } from 'react-native';

const light = {
  bg: '#EEF2F0', surface: '#FFFFFF', sunk: '#F5F8F6', ink: '#15211E', muted: '#596A66', line: '#D8E1DD',
  brand: '#0E5A50', brandSoft: '#DCEDE9', accent: '#E8931A', accentInk: '#2E1D00', accentSoft: '#FCEBD0',
  ok: '#1C7F47', okSoft: '#DDF1E5', warn: '#A86400', warnSoft: '#FBEBCF', bad: '#B23A2E', badSoft: '#F8DEDA', onBrand: '#FFFFFF',
};
const dark = {
  bg: '#0C1311', surface: '#141E1B', sunk: '#101916', ink: '#E4EDEA', muted: '#93A5A0', line: '#25332F',
  brand: '#5CBFB0', brandSoft: '#173430', accent: '#F2A53A', accentInk: '#241600', accentSoft: '#3A2A10',
  ok: '#58C98A', okSoft: '#143322', warn: '#E9AE4B', warnSoft: '#352812', bad: '#EE7B6E', badSoft: '#3A1A16', onBrand: '#0C1311',
};

export const useTheme = () => (useColorScheme() === 'dark' ? dark : light);
export const mono = { fontVariant: ['tabular-nums'], fontWeight: '700' };
