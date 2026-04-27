'use client';

import { RxChevronRight } from 'react-icons/rx';
import { Button } from '@relume_io/relume-ui';
import React from 'react';

export function Layout431() {
  return (
    <section id="relume" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container">
        <div className="md:mb-18 mb-12 lg:mb-20">
          <div className="max-w-md">
            <p className="mb-3 font-semibold md:mb-4">Seamless</p>
            <h2 className="mb-5 text-5xl font-bold md:mb-6 md:text-7xl lg:text-8xl">
              Your data, always in sync
            </h2>
          </div>
        </div>
        <div className="grid grid-cols-1 items-end gap-x-16 gap-y-12 md:grid-cols-[1fr_0.75fr]">
          <div className="grid grid-cols-2 gap-6 sm:gap-8">
            <img
              src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image.svg"
              className="w-full object-cover"
              width="640"
              height="640"
              alt="Mac and web content staying in sync in Todus"
            />
            <img
              src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image.svg"
              className="mt-[25%] w-full object-cover"
              width="640"
              height="640"
              alt="Updates from Todus appearing instantly on mobile"
            />
          </div>
          <div>
            <div className="ml-[5%] mr-[10%]">
              <p className="md:text-base">
                All your tasks, emails, and notes are seamlessly updated across every platform.
                Change something on your phone, and it's there on your Mac. No lag, no confusion, no
                manual refresh.
              </p>
              <div className="mt-6 flex flex-wrap gap-4 md:mt-8">
                <Button title="Download" variant="secondary">
                  Download
                </Button>
                <Button
                  title="Learn more"
                  variant="link"
                  size="link"
                  iconRight={<RxChevronRight />}
                >
                  Learn more
                </Button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
