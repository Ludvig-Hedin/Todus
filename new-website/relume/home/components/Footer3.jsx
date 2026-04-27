'use client';

import {
  BiLogoFacebookCircle,
  BiLogoInstagram,
  BiLogoLinkedinSquare,
  BiLogoYoutube,
} from 'react-icons/bi';
import { FaXTwitter } from 'react-icons/fa6';
import React from 'react';

export function Footer3() {
  return (
    <footer id="relume" className="px-[5%] py-8 md:py-12 lg:py-16">
      <div className="container">
        <div className="grid grid-cols-1 gap-x-[4vw] gap-y-12 pb-8 md:gap-y-12 md:pb-12 lg:grid-cols-[1fr_0.5fr] lg:gap-y-4 lg:pb-16">
          <div>
            <div className="mb-6 md:mb-8">
              <a href="#" className="flex items-center">
                <span className="text-lg font-semibold tracking-tight">Todus</span>
              </a>
            </div>
            <div className="mb-6 md:mb-8">
              <p className="mb-1 text-sm font-semibold tracking-tight">Email</p>
              <a
                href="mailto:hello@todus.app"
                className="block text-sm tracking-tight underline decoration-black underline-offset-1"
              >
                hello@todus.app
              </a>
            </div>
          </div>
          <div className="grid grid-cols-1 items-start gap-x-6 gap-y-10 md:grid-cols-2 md:gap-x-8 md:gap-y-4">
            <ul>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Features</a>
              </li>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Pricing</a>
              </li>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Download</a>
              </li>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Blog</a>
              </li>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Company</a>
              </li>
            </ul>
            <ul>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Contact</a>
              </li>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Careers</a>
              </li>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Press</a>
              </li>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Legal</a>
              </li>
              <li className="py-2 text-sm font-semibold tracking-tight">
                <a href="#">Privacy</a>
              </li>
            </ul>
          </div>
        </div>
        <div className="bg-border-primary/50 h-px w-full" />
        <div className="flex flex-col-reverse items-start justify-between pb-4 pt-6 text-sm tracking-tight md:flex-row md:items-center md:pb-0 md:pt-8">
          <p className="text-text-alternative mt-8 md:mt-0">© 2025 Todus</p>
          <ul className="grid grid-flow-row grid-cols-[max-content] justify-center gap-y-4 text-sm tracking-tight md:grid-flow-col md:gap-x-6 md:gap-y-0">
            <li className="text-text-alternative underline">
              <a href="#">Privacy Policy</a>
            </li>
            <li className="text-text-alternative underline">
              <a href="#">Terms of Service</a>
            </li>
            <li className="text-text-alternative underline">
              <a href="#">Cookie Settings</a>
            </li>
          </ul>
        </div>
      </div>
    </footer>
  );
}
