import { AnimatePresence, motion } from 'motion/react';
import type { SceneId } from './mockData';
import { SceneInbox } from './scenes/SceneInbox';
import { SceneCalendar } from './scenes/SceneCalendar';
import { SceneTasks } from './scenes/SceneTasks';
import { SceneAssistant } from './scenes/SceneAssistant';

export function DemoStage({
  active,
  compact = false,
}: {
  active: SceneId;
  compact?: boolean;
}) {
  return (
    <div className="relative h-full w-full">
      <AnimatePresence mode="wait">
        <motion.div
          key={active}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -4 }}
          transition={{ duration: 0.32, ease: [0.16, 1, 0.3, 1] }}
          className="absolute inset-0"
        >
          {active === 'mail' && <SceneInbox compact={compact} />}
          {active === 'calendar' && <SceneCalendar compact={compact} />}
          {active === 'tasks' && <SceneTasks compact={compact} />}
          {active === 'assistant' && <SceneAssistant compact={compact} />}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
