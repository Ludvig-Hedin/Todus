/**
 * SwipeableThreadRow — wraps a thread list item with swipe-to-archive (right)
 * and swipe-to-delete (left) actions, with haptic feedback.
 */
import React, { useCallback, useRef } from 'react';
import { Animated, StyleSheet, View } from 'react-native';
import { Swipeable } from 'react-native-gesture-handler';
import { Archive, Trash2 } from 'lucide-react-native';
import { useTheme } from '../../shared/theme/ThemeContext';
import { haptics } from '../../shared/utils/haptics';

interface SwipeableThreadRowProps {
  children: React.ReactNode;
  onArchive: () => void;
  onDelete: () => void;
}

export function SwipeableThreadRow({ children, onArchive, onDelete }: SwipeableThreadRowProps) {
  const { colors } = useTheme();
  const swipeableRef = useRef<Swipeable>(null);

  const handleArchive = useCallback(() => {
    haptics.success();
    swipeableRef.current?.close();
    onArchive();
  }, [onArchive]);

  const handleDelete = useCallback(() => {
    haptics.warning();
    swipeableRef.current?.close();
    onDelete();
  }, [onDelete]);

  // Swipe right → green archive action
  const renderLeftActions = (_progress: Animated.AnimatedInterpolation<number>, dragX: Animated.AnimatedInterpolation<number>) => {
    const scale = dragX.interpolate({
      inputRange: [0, 80],
      outputRange: [0.5, 1],
      extrapolate: 'clamp',
    });
    return (
      <View style={[styles.leftAction, { backgroundColor: '#22c55e' }]}>
        <Animated.View style={{ transform: [{ scale }] }}>
          <Archive size={22} color="#fff" />
        </Animated.View>
      </View>
    );
  };

  // Swipe left → red delete action
  const renderRightActions = (_progress: Animated.AnimatedInterpolation<number>, dragX: Animated.AnimatedInterpolation<number>) => {
    const scale = dragX.interpolate({
      inputRange: [-80, 0],
      outputRange: [1, 0.5],
      extrapolate: 'clamp',
    });
    return (
      <View style={[styles.rightAction, { backgroundColor: colors.destructive }]}>
        <Animated.View style={{ transform: [{ scale }] }}>
          <Trash2 size={22} color="#fff" />
        </Animated.View>
      </View>
    );
  };

  return (
    <Swipeable
      ref={swipeableRef}
      renderLeftActions={renderLeftActions}
      renderRightActions={renderRightActions}
      onSwipeableOpen={(direction) => {
        if (direction === 'left') handleArchive();
        else if (direction === 'right') handleDelete();
      }}
      leftThreshold={80}
      rightThreshold={80}
      friction={2}
      overshootLeft={false}
      overshootRight={false}
    >
      {children}
    </Swipeable>
  );
}

const styles = StyleSheet.create({
  leftAction: {
    flex: 1,
    justifyContent: 'center',
    paddingLeft: 24,
  },
  rightAction: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'flex-end',
    paddingRight: 24,
  },
});
