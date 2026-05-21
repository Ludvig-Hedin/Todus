import { Menu } from 'lucide-react';
import { TodusLogo } from '@/components/ui/todus-logo';

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { Button } from '@/components/ui/button';
import {
  NavigationMenu,
  NavigationMenuContent,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  NavigationMenuTrigger,
} from '@/components/ui/navigation-menu';
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';
import { cn } from '@/lib/utils';
import { Link } from 'react-router';

interface MenuItem {
  title: string;
  url: string;
  description?: string;
  icon?: React.ReactNode;
  items?: MenuItem[];
}

interface Navbar1Props {
  className?: string;
  logo?: {
    url: string;
    src: string;
    alt: string;
    title: string;
  };
  menu?: MenuItem[];
  onGetStarted?: () => void;
  sessionExists?: boolean;
}

const Navbar1 = ({
  logo = {
    url: '/',
    src: '/brand-logo.png',
    alt: 'Logo',
    title: 'App',
  },
  menu = [],
  onGetStarted,
  sessionExists,
  className,
}: Navbar1Props) => {
  return (
    <section className={cn('w-full', className)}>
      {/* Desktop */}
      <nav className="hidden items-center justify-between px-6 py-3 lg:flex">
        <div className="flex items-center gap-6">
          <Link to={logo.url}>
            <TodusLogo height={18} className="text-white" />
          </Link>
          <NavigationMenu delayDuration={0}>
            <NavigationMenuList className="gap-0">
              {menu.map((item) => renderMenuItem(item))}
            </NavigationMenuList>
          </NavigationMenu>
        </div>
        <div className="flex items-center gap-2">
          {sessionExists ? (
            <Button
              size="sm"
              className="h-8 bg-white text-black hover:bg-white/90 hover:text-black"
              onClick={onGetStarted}
            >
              Open inbox
            </Button>
          ) : (
            <>
              <Button
                asChild
                variant="outline"
                size="sm"
                className="h-8 border-white/20 bg-transparent text-white/70 hover:border-white/40 hover:bg-transparent hover:text-white"
              >
                <Link to="/login">Log in</Link>
              </Button>
              <Button
                size="sm"
                className="h-8 bg-white text-black hover:bg-white/90 hover:text-black"
                onClick={onGetStarted}
              >
                Get Started
              </Button>
            </>
          )}
        </div>
      </nav>

      {/* Mobile */}
      <div className="block lg:hidden">
        <div className="flex items-center justify-between px-4 py-3">
          <Link to={logo.url}>
            <TodusLogo height={18} className="text-white" />
          </Link>
          <Sheet>
            <SheetTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="text-white/70 hover:bg-white/10 hover:text-white"
              >
                <Menu className="size-5" />
              </Button>
            </SheetTrigger>
            <SheetContent className="overflow-y-auto dark:bg-[#111111]">
              <SheetHeader>
                <SheetTitle>
                  <Link to={logo.url}>
                    <TodusLogo height={18} className="text-white" />
                  </Link>
                </SheetTitle>
              </SheetHeader>
              <div className="flex flex-col gap-6 p-4">
                <Accordion type="single" collapsible className="flex w-full flex-col gap-4">
                  {menu.map((item) => renderMobileMenuItem(item))}
                </Accordion>
                <div className="flex flex-col gap-3">
                  {!sessionExists && (
                    <Button asChild variant="outline">
                      <Link to="/login">Log in</Link>
                    </Button>
                  )}
                  <Button onClick={onGetStarted}>
                    {sessionExists ? 'Open inbox' : 'Get Started'}
                  </Button>
                </div>
              </div>
            </SheetContent>
          </Sheet>
        </div>
      </div>
    </section>
  );
};

const renderMenuItem = (item: MenuItem) => {
  if (item.items) {
    return (
      <NavigationMenuItem key={item.title}>
        <NavigationMenuTrigger className="bg-transparent text-white/70 hover:bg-white/10 hover:text-white data-[state=open]:bg-white/10 data-[state=open]:text-white h-9 text-sm">
          {item.title}
        </NavigationMenuTrigger>
        <NavigationMenuContent className="bg-popover text-popover-foreground">
          <div className="p-2">
            {item.items.map((subItem) => (
              <NavigationMenuLink asChild key={subItem.title}>
                <SubMenuLink item={subItem} />
              </NavigationMenuLink>
            ))}
          </div>
        </NavigationMenuContent>
      </NavigationMenuItem>
    );
  }

  return (
    <NavigationMenuItem key={item.title}>
      <NavigationMenuLink
        href={item.url}
        className="inline-flex h-9 w-max items-center justify-center rounded-md px-4 py-2 text-sm text-white/70 transition-colors hover:bg-white/10 hover:text-white"
      >
        {item.title}
      </NavigationMenuLink>
    </NavigationMenuItem>
  );
};

const renderMobileMenuItem = (item: MenuItem) => {
  if (item.items) {
    return (
      <AccordionItem key={item.title} value={item.title} className="border-b-0">
        <AccordionTrigger className="py-0 text-sm font-semibold hover:no-underline">
          {item.title}
        </AccordionTrigger>
        <AccordionContent className="mt-2">
          {item.items.map((subItem) => (
            <SubMenuLink key={subItem.title} item={subItem} />
          ))}
        </AccordionContent>
      </AccordionItem>
    );
  }

  return (
    <a key={item.title} href={item.url} className="text-sm font-semibold">
      {item.title}
    </a>
  );
};

const SubMenuLink = ({ item }: { item: MenuItem }) => {
  return (
    <a
      className="flex min-w-80 flex-row gap-4 rounded-md p-3 leading-none no-underline outline-none transition-colors select-none hover:bg-muted hover:text-accent-foreground"
      href={item.url}
    >
      <div className="text-foreground">{item.icon}</div>
      <div>
        <div className="text-sm font-semibold">{item.title}</div>
        {item.description && (
          <p className="text-sm leading-snug text-muted-foreground">{item.description}</p>
        )}
      </div>
    </a>
  );
};

export { Navbar1 };
