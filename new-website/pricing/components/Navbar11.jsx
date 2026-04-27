'use client';

import { Button, useMediaQuery } from '@relume_io/relume-ui';
import { AnimatePresence, motion } from 'framer-motion';
import { RxChevronDown } from 'react-icons/rx';
import React, { useState } from 'react';

const useRelume = () => {
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const isMobile = useMediaQuery('(max-width: 991px)');
  const toggleMobileMenu = () => setIsMobileMenuOpen((prev) => !prev);
  const openOnMobileDropdownMenu = () => {
    setIsDropdownOpen((prev) => !prev);
  };
  const openOnDesktopDropdownMenu = () => {
    !isMobile && setIsDropdownOpen(true);
  };
  const closeOnDesktopDropdownMenu = () => {
    !isMobile && setIsDropdownOpen(false);
  };
  const animateMobileMenu = isMobileMenuOpen ? 'open' : 'close';
  const animateMobileMenuButtonSpan = isMobileMenuOpen ? ['open', 'rotatePhase'] : 'closed';
  const animateDropdownMenu = isDropdownOpen ? 'open' : 'close';
  const animateDropdownMenuIcon = isDropdownOpen ? 'rotated' : 'initial';
  return {
    isMobileMenuOpen,
    isDropdownOpen,
    toggleMobileMenu,
    openOnDesktopDropdownMenu,
    closeOnDesktopDropdownMenu,
    openOnMobileDropdownMenu,
    animateMobileMenu,
    animateMobileMenuButtonSpan,
    animateDropdownMenu,
    animateDropdownMenuIcon,
  };
};

export function Navbar11() {
  const useActive = useRelume();
  return (
    <section
      id="relume"
      className="bg-background-primary flex w-full items-center md:min-h-14 lg:px-[5%]"
    >
      <div className="mx-auto size-full items-center justify-between lg:flex">
        <div className="grid min-h-12 grid-cols-2 items-center justify-between px-[5%] md:min-h-14 lg:min-h-full lg:px-0">
          <a href="#" className="flex items-center">
            <span className="text-lg font-semibold tracking-tight">Todus</span>
          </a>
          <button
            className="-mr-2 flex size-12 flex-col items-center justify-center justify-self-end lg:hidden"
            onClick={useActive.toggleMobileMenu}
            aria-label="Toggle mobile menu"
            aria-expanded={useActive.isMobileMenuOpen}
            aria-controls="mobile-navigation-menu"
          >
            <motion.span
              className="my-[3px] h-0.5 w-6 bg-black"
              animate={useActive.animateMobileMenuButtonSpan}
              variants={{
                open: { translateY: 8, transition: { delay: 0.1 } },
                rotatePhase: { rotate: -45, transition: { delay: 0.2 } },
                closed: {
                  translateY: 0,
                  rotate: 0,
                  transition: { duration: 0.2 },
                },
              }}
            />
            <motion.span
              className="my-[3px] h-0.5 w-6 bg-black"
              animate={useActive.animateMobileMenu}
              variants={{
                open: { width: 0, transition: { duration: 0.1 } },
                closed: {
                  width: '1.5rem',
                  transition: { delay: 0.3, duration: 0.2 },
                },
              }}
            />
            <motion.span
              className="my-[3px] h-0.5 w-6 bg-black"
              animate={useActive.animateMobileMenuButtonSpan}
              variants={{
                open: { translateY: -8, transition: { delay: 0.1 } },
                rotatePhase: { rotate: 45, transition: { delay: 0.2 } },
                closed: {
                  translateY: 0,
                  rotate: 0,
                  transition: { duration: 0.2 },
                },
              }}
            />
          </button>
        </div>
        <motion.div
          id="mobile-navigation-menu"
          variants={{
            open: { height: 'var(--height-open, 100dvh)' },
            close: { height: 'var(--height-closed, 0)' },
          }}
          initial="close"
          exit="close"
          animate={useActive.animateMobileMenu}
          transition={{ duration: 0.3 }}
          className="overflow-hidden px-[5%] lg:flex lg:items-center lg:px-0 lg:[--height-closed:auto] lg:[--height-open:auto]"
        >
          <nav className="lg:flex lg:items-center">
            <a
              href="#"
              className="block py-2 text-left text-sm tracking-tight first:pt-5 lg:px-4 lg:py-2 lg:first:pt-2"
            >
              Features
            </a>
            <a
              href="#"
              className="block py-2 text-left text-sm tracking-tight first:pt-5 lg:px-4 lg:py-2 lg:first:pt-2"
            >
              Pricing
            </a>
            <a
              href="#"
              className="block py-2 text-left text-sm tracking-tight first:pt-5 lg:px-4 lg:py-2 lg:first:pt-2"
            >
              Blog
            </a>
            <div
              onMouseEnter={useActive.openOnDesktopDropdownMenu}
              onMouseLeave={useActive.closeOnDesktopDropdownMenu}
            >
              <button
                className="flex w-full items-center justify-between gap-2 py-2 text-left text-sm tracking-tight lg:flex-none lg:justify-start lg:px-4 lg:py-2"
                onClick={useActive.openOnMobileDropdownMenu}
                aria-haspopup="menu"
                aria-expanded={useActive.isDropdownOpen}
                aria-controls="mobile-dropdown-menu"
              >
                <span>More</span>
                <AnimatePresence>
                  <motion.div
                    animate={useActive.animateDropdownMenuIcon}
                    variants={{
                      rotated: { rotate: 180 },
                      initial: { rotate: 0 },
                    }}
                    transition={{ duration: 0.3 }}
                  >
                    <RxChevronDown />
                  </motion.div>
                </AnimatePresence>
              </button>
              <AnimatePresence>
                <motion.nav
                  id="mobile-dropdown-menu"
                  role="menu"
                  animate={useActive.animateDropdownMenu}
                  initial="close"
                  exit="close"
                  variants={{
                    open: {
                      visibility: 'visible',
                      opacity: 'var(--opacity-open, 100%)',
                      y: 0,
                      display: 'block',
                    },
                    close: {
                      visibility: 'hidden',
                      opacity: 'var(--opacity-close, 0)',
                      y: 'var(--y-close, 0%)',
                      display: 'none',
                    },
                  }}
                  transition={{ duration: 0.3 }}
                  className="bg-background-primary lg:border-border-primary z-50 lg:absolute lg:w-80 lg:border lg:p-6 lg:[--y-close:25%]"
                >
                  <div className="grid grid-cols-1 grid-rows-[max-content] gap-y-2 py-3 md:py-3 lg:gap-y-4 lg:py-0">
                    <a
                      href="#"
                      className="grid auto-cols-fr grid-cols-[max-content_1fr] items-start gap-x-3 py-2 lg:py-1"
                    >
                      <div className="flex flex-col items-start justify-center">
                        <p className="text-sm font-semibold tracking-tight">Legal</p>
                        <p className="text-text-alternative hidden text-xs tracking-tight md:block">
                          Terms of service and privacy
                        </p>
                      </div>
                    </a>
                    <a
                      href="#"
                      className="grid auto-cols-fr grid-cols-[max-content_1fr] items-start gap-x-3 py-2 lg:py-1"
                    >
                      <div className="flex flex-col items-start justify-center">
                        <p className="text-sm font-semibold tracking-tight">Download</p>
                        <p className="text-text-alternative hidden text-xs tracking-tight md:block">
                          Get Todus on your device
                        </p>
                      </div>
                    </a>
                    <a
                      href="#"
                      className="grid auto-cols-fr grid-cols-[max-content_1fr] items-start gap-x-3 py-2 lg:py-1"
                    >
                      <div className="flex flex-col items-start justify-center">
                        <p className="text-sm font-semibold tracking-tight">Contact</p>
                        <p className="text-text-alternative hidden text-xs tracking-tight md:block">
                          Reach out to our team
                        </p>
                      </div>
                    </a>
                    <a
                      href="#"
                      className="grid auto-cols-fr grid-cols-[max-content_1fr] items-start gap-x-3 py-2 lg:py-1"
                    >
                      <div className="flex flex-col items-start justify-center">
                        <p className="text-sm font-semibold tracking-tight">Home</p>
                        <p className="text-text-alternative hidden text-xs tracking-tight md:block">
                          Back to the main page
                        </p>
                      </div>
                    </a>
                  </div>
                </motion.nav>
              </AnimatePresence>
            </div>
          </nav>
          <div className="mt-6 flex flex-col gap-4 lg:ml-4 lg:mt-0 lg:flex-row lg:items-center">
            <Button title="Get Todus" size="sm" className="rounded-full">
              Get Todus
            </Button>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
