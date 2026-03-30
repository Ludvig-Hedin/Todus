import { NavLink, Outlet, useLocation } from "react-router";
import { Home, CheckSquare, Mail, Calendar, Settings, Sparkles, Plus, Bell } from "lucide-react";
import { cn } from "../../lib/utils";

export function AppLayout() {
  const location = useLocation();

  const navItems = [
    { name: "Home", path: "/home", icon: Home },
    { name: "Tasks", path: "/tasks", icon: CheckSquare },
    { name: "Email", path: "/mail", icon: Mail },
    { name: "Calendar", path: "/calendar", icon: Calendar },
  ];

  // Get a title for the mobile header based on the current path
  const currentTitle = navItems.find(item => location.pathname.startsWith(item.path))?.name || "Todus";

  return (
    <div className="flex h-[100dvh] w-full bg-background text-foreground overflow-hidden">
      {/* ================= DESKTOP SIDEBAR (macOS Mirror) ================= */}
      <aside className="hidden md:flex flex-col w-64 border-r border-border bg-card">
        <div className="p-4 flex items-center gap-3 font-semibold text-lg border-b border-border/40">
          <div className="w-8 h-8 rounded-lg bg-primary text-primary-foreground flex items-center justify-center font-bold">
            T
          </div>
          Todus
        </div>
        <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
          {navItems.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive }) => cn(
                "flex items-center gap-3 px-3 py-2 rounded-md transition-all duration-150 text-[13px] font-medium",
                isActive 
                  ? "bg-accent text-accent-foreground shadow-sm" 
                  : "hover:bg-accent/50 text-muted-foreground hover:text-foreground"
              )}
            >
              <item.icon className="w-4 h-4" />
              {item.name}
            </NavLink>
          ))}
        </nav>
        <div className="p-4 border-t border-border/40">
          <NavLink to="/settings" className={({ isActive }) => cn(
            "flex items-center gap-3 px-3 py-2 rounded-md transition-all duration-150 text-[13px] font-medium",
            isActive 
              ? "bg-accent text-accent-foreground shadow-sm" 
              : "hover:bg-accent/50 text-muted-foreground hover:text-foreground"
          )}>
            <Settings className="w-4 h-4" />
            Settings
          </NavLink>
        </div>
      </aside>

      {/* ================= MAIN CONTENT AREA ================= */}
      <main className="flex-1 flex flex-col min-w-0 relative">
        {/* Universal Top Header */}
        <header className="h-14 border-b border-border bg-background/80 backdrop-blur-md flex items-center justify-between px-4 shrink-0 z-10">
          <div className="flex items-center gap-2">
            <span className="font-semibold text-lg md:hidden">{currentTitle}</span>
          </div>
          <div className="flex items-center gap-4">
            <button className="text-muted-foreground hover:text-foreground transition-colors">
              <Bell className="w-5 h-5" />
            </button>
            <div className="w-8 h-8 rounded-full bg-accent border border-border flex items-center justify-center text-xs font-medium">
              U
            </div>
          </div>
        </header>

        {/* Page Content Outlet */}
        <div className="flex-1 overflow-auto bg-background p-4 md:p-6 pb-24 md:pb-6 relative">
          <Outlet />
        </div>

        {/* Desktop Floating AI Button */}
        <button className="hidden md:flex absolute bottom-6 right-6 w-12 h-12 bg-primary text-primary-foreground rounded-full shadow-lg items-center justify-center hover:opacity-90 transition-opacity z-50">
          <Sparkles className="w-5 h-5" />
        </button>
      </main>

      {/* ================= MOBILE TAB BAR (iOS Mirror) ================= */}
      <nav className="md:hidden fixed bottom-0 left-0 right-0 h-16 border-t border-border bg-card/90 backdrop-blur-lg flex items-center justify-around px-2 z-40 pb-safe">
        {navItems.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            className={({ isActive }) => cn(
              "flex flex-col items-center justify-center w-16 h-full gap-1 transition-colors",
              isActive ? "text-primary" : "text-muted-foreground"
            )}
          >
            <item.icon className="w-5 h-5" />
          </NavLink>
        ))}
      </nav>

      {/* ================= MOBILE FLOATING ACTIONS (iOS Mirror) ================= */}
      <div className="md:hidden fixed bottom-20 right-4 flex flex-col gap-3 z-50">
        {/* Universal Create (FAB) */}
        <button className="w-14 h-14 bg-primary text-primary-foreground rounded-full shadow-xl flex items-center justify-center hover:opacity-90 transition-opacity">
          <Plus className="w-6 h-6" />
        </button>
        {/* AI Assistant */}
        <button className="w-12 h-12 bg-card text-card-foreground border border-border rounded-full shadow-lg flex items-center justify-center hover:bg-accent transition-colors mx-auto">
          <Sparkles className="w-5 h-5 text-primary" />
        </button>
      </div>
    </div>
  );
}