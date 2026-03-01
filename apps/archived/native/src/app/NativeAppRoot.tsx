import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { StyleSheet } from 'react-native';
import { AppProviders } from './providers/AppProviders';
import { RootNavigator } from './navigation/RootNavigator';

export function NativeAppRoot() {
  return (
    <GestureHandlerRootView style={styles.root}>
      <AppProviders>
        <RootNavigator />
      </AppProviders>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
});
