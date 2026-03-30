import { type RouteConfig, index, route, layout } from "@react-router/dev/routes";

export default [
  layout("components/layout/app-layout.tsx", [
    index("(routes)/home/page.tsx"),
    route("home", "(routes)/home/page.tsx"),
    route("tasks", "(routes)/tasks/page.tsx"),
    route("calendar", "(routes)/calendar/page.tsx"),
    route("settings", "(routes)/settings/page.tsx"),
    
    // Mail acts as a temporary placeholder while we port over the existing components
    route("mail", "(routes)/mail/page.tsx"),
  ])
] satisfies RouteConfig;