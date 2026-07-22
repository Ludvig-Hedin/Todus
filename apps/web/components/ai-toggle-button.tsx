import { useAISidebar, useAssistantDisplayMode } from '@/hooks/use-ai-sidebar';
import { Tooltip, TooltipTrigger, TooltipContent } from './ui/tooltip';

// Sparkles constellation matching SF Symbol "sparkles" on iOS/macOS. Painted
// with the same 4-stop linear gradient as `AssistantButton.swift` (151deg-ish:
// cyan → magenta → red → amber). Inline SVG, no SF Symbol dependency.
const AIFabSparkleIcon = ({ size = 18 }: { size?: number }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    aria-hidden="true"
  >
    <defs>
      <linearGradient
        id="ai-fab-sparkle-gradient"
        x1="7.2"
        y1="0"
        x2="16.8"
        y2="24"
        gradientUnits="userSpaceOnUse"
      >
        <stop offset="0%" stopColor="#00AAF5" />
        <stop offset="33%" stopColor="#EF00C2" />
        <stop offset="66%" stopColor="#FF0038" />
        <stop offset="100%" stopColor="#F99F00" />
      </linearGradient>
    </defs>
    {/* Large 4-pointed star (centered, lower-right bias) */}
    <path
      d="M14.5 4 C14.5 8.7 10.7 12.5 6 12.5 C10.7 12.5 14.5 16.3 14.5 21 C14.5 16.3 18.3 12.5 23 12.5 C18.3 12.5 14.5 8.7 14.5 4 Z"
      fill="url(#ai-fab-sparkle-gradient)"
    />
    {/* Small 4-pointed star (upper-left) */}
    <path
      d="M5 0.5 C5 2.4 3.4 4 1.5 4 C3.4 4 5 5.6 5 7.5 C5 5.6 6.6 4 8.5 4 C6.6 4 5 2.4 5 0.5 Z"
      fill="url(#ai-fab-sparkle-gradient)"
    />
  </svg>
);

// AI Toggle Button — capsule "Assistant" pill matching the macOS `AssistantButton`
// (sparkle icon + label, ultra-thick material background, subtle stroke + shadow).
// Opens the assistant in whichever display mode the user last picked.
const AIToggleButton = () => {
  const { toggleOpen: toggleAISidebar, open: isSidebarOpen, setIsFullScreen } = useAISidebar();
  // We don't change the mode here, but reading it keeps the hook tree stable and lets
  // future iterations branch the icon by mode without another refactor.
  useAssistantDisplayMode(setIsFullScreen);

  return (
    !isSidebarOpen && (
      <div className="fixed bottom-5 right-5 z-50">
        <Tooltip>
          <TooltipTrigger asChild>
            <button
              type="button"
              onClick={(e) => {
                if (!isSidebarOpen) {
                  e.stopPropagation();
                  toggleAISidebar();
                }
              }}
              aria-label="Open AI Assistant"
              className="dark:bg-sidebar/85 border-foreground/10 bg-background/85 duration-(--motion-duration-fast) ease-(--motion-easing-standard) group inline-flex h-11 items-center gap-2 rounded-full border px-4 shadow-[0_8px_24px_-8px_rgba(0,0,0,0.35)] backdrop-blur-xl transition-[transform,opacity,box-shadow] hover:scale-[1.02] hover:shadow-[0_12px_32px_-10px_rgba(0,0,0,0.45)] active:scale-[0.98]"
            >
              <AIFabSparkleIcon size={20} />
              <span className="text-foreground/70 group-hover:text-foreground text-[13px] font-medium">
                Assistant
              </span>
            </button>
          </TooltipTrigger>
          <TooltipContent>Ask AI — Cmd/Ctrl+Shift+L for floating mode</TooltipContent>
        </Tooltip>
      </div>
    )
  );
};

export default AIToggleButton;
