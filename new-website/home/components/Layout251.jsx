'use client';

import { RxChevronRight } from 'react-icons/rx';
import { Button } from '@relume_io/relume-ui';
import React from 'react';

export function Layout251() {
  return (
    <section id="relume" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container">
        <div className="md:mb-18 mb-12 grid grid-cols-1 items-start gap-5 md:grid-cols-2 md:gap-x-12 lg:mb-20 lg:gap-x-20">
          <div>
            <p className="mb-3 font-semibold md:mb-4">Why</p>
            <h2 className="text-5xl font-bold md:text-7xl lg:text-8xl">
              One app beats five apps every time
            </h2>
          </div>
          <div>
            <p className="md:text-base">
              Most people lose over 20 minutes a day switching between tools. Todus removes that
              friction so you can focus on what matters.
            </p>
          </div>
        </div>
        <div className="grid grid-cols-1 items-start gap-y-12 md:grid-cols-3 md:gap-x-8 lg:gap-x-12">
          <div>
            <div className="mb-6 md:mb-8">
              <img
                src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image-landscape.svg"
                alt="Relume placeholder image"
              />
            </div>
            <h3 className="mb-5 text-2xl font-bold md:mb-6 md:text-3xl md:leading-[1.3] lg:text-4xl">
              Twenty minutes lost to refocus
            </h3>
            <p>Average time saved by consolidating email, calendar, and tasks.</p>
          </div>
          <div>
            <div className="mb-6 md:mb-8">
              <img
                src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image-landscape.svg"
                alt="Relume placeholder image"
              />
            </div>
            <h3 className="mb-5 text-2xl font-bold md:mb-6 md:text-3xl md:leading-[1.3] lg:text-4xl">
              Everything connects, nothing gets lost
            </h3>
            <p>Emails become tasks. Tasks appear on your calendar. Notes attach to projects.</p>
          </div>
          <div>
            <div className="mb-6 md:mb-8">
              <img
                src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image-landscape.svg"
                alt="Relume placeholder image"
              />
            </div>
            <h3 className="mb-5 text-2xl font-bold md:mb-6 md:text-3xl md:leading-[1.3] lg:text-4xl">
              One rhythm across all your devices
            </h3>
            <p>Same app on phone, Mac, and web. No learning curve, no lite versions.</p>
          </div>
        </div>
        <div className="md:mt-18 mt-12 flex items-center gap-4 lg:mt-20">
          <Button variant="secondary">Explore</Button>
          <Button iconRight={<RxChevronRight />} variant="link" size="link">
            Learn more
          </Button>
        </div>
      </div>
    </section>
  );
}
