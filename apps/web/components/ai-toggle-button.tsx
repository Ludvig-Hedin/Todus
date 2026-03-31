import { Tooltip, TooltipTrigger, TooltipContent } from './ui/tooltip';
import { useAISidebar } from './ui/ai-sidebar';
import { Button } from './ui/button';

// Fixed circular FAB that opens the AI assistant popup.
// Circular (rounded-full) with subtle glass-card feel and soft drop shadow.
const AIToggleButton = () => {
  const { toggleOpen: toggleAISidebar, open: isSidebarOpen } = useAISidebar();

  return (
    !isSidebarOpen && (
      <div className="fixed bottom-5 right-5 z-50">
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              className="h-11 w-11 rounded-full border border-border/50 bg-background/95 shadow-md backdrop-blur-sm transition-all hover:shadow-lg"
              onClick={(e) => {
                if (!isSidebarOpen) {
                  e.stopPropagation();
                  toggleAISidebar();
                }
              }}
            >
              <div className="flex items-center justify-center">
                <img
                  src="/black-icon.svg"
                  alt="AI Assistant"
                  width={20}
                  height={20}
                  className="block dark:hidden"
                />
                <img
                  src="/white-icon.svg"
                  alt="AI Assistant"
                  width={20}
                  height={20}
                  className="hidden dark:block"
                />
              </div>
            </Button>
          </TooltipTrigger>
          <TooltipContent side="left">AI Assistant</TooltipContent>
        </Tooltip>
      </div>
    )
  );
};

export default AIToggleButton;
