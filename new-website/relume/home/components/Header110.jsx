'use client';

import { Button } from '@relume_io/relume-ui';
import React from 'react';

export function Header110() {
  return (
    <section id="relume" className="px-[5%] py-12 md:py-16 lg:py-20">
      <div className="container grid grid-cols-1 gap-12 md:grid-cols-[0.5fr_1fr] md:gap-16">
        <div className="flex h-full flex-col justify-between">
          <h2 className="mb-5 text-5xl font-bold tracking-tight md:mb-6 md:text-7xl lg:text-8xl">
            Your entire day, finally in one place
          </h2>
          <div className="ml-[7.5%]">
            <p className="md:text-md text-text-alternative tracking-tight">
              All your email, calendar, tasks, notes, and AI assistant in a single app. Minimal,
              powerful, and fast everywhere.
            </p>
            <div className="mt-6 flex flex-wrap gap-4 md:mt-8 md:flex-wrap">
              <Button title="Get Todus" className="rounded-full">
                Get Todus
              </Button>
              <Button title="See how it works" variant="secondary" className="rounded-full">
                See how it works
              </Button>
            </div>
          </div>
        </div>
        <div className="grid grid-cols-[1fr_0.75fr] items-start gap-6 sm:gap-8">
          <div className="w-full">
            <img
              src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image.svg"
              alt="Relume placeholder image 1"
              className="aspect-[2/3] size-full rounded-2xl object-cover"
            />
          </div>
          <div className="w-full">
            <img
              src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image-landscape.svg"
              alt="Relume placeholder image 2"
              className="aspect-square size-full rounded-2xl object-cover"
            />
          </div>
        </div>
      </div>
    </section>
  );
}
