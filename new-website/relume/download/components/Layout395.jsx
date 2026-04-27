"use client";

import { Button } from "@relume_io/relume-ui";
import React from "react";
import { RxChevronRight } from "react-icons/rx";

export function Layout395() {
  return (
    <section id="relume" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container">
        <div className="mx-auto mb-12 w-full max-w-lg text-center md:mb-18 lg:mb-20">
          <p className="mb-3 font-semibold md:mb-4">Platforms</p>
          <h1 className="mb-5 text-5xl font-bold md:mb-6 md:text-7xl lg:text-8xl">
            Built for every device you use
          </h1>
          <p className="md:text-md">
            One app, one experience. Whether you're on your phone, Mac, or at
            your desk, Todus feels native and instant.
          </p>
        </div>
        <div className="grid auto-cols-fr grid-cols-1 gap-6 md:gap-8 lg:grid-cols-3">
          <div className="flex flex-col border border-border-primary">
            <div className="flex w-full flex-col items-center justify-center self-start">
              <img
                src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image.svg"
                alt="Relume placeholder image 1"
              />
            </div>
            <div className="flex flex-1 flex-col justify-center p-6 md:p-8">
              <div>
                <p className="mb-2 font-semibold">macOS</p>
                <h2 className="mb-3 text-2xl font-bold md:mb-4 md:text-3xl md:leading-[1.3] lg:text-4xl">
                  macOS app
                </h2>
                <p>
                  Fast, native, and built for power users who live in their
                  inbox and calendar.
                </p>
              </div>
              <div className="mt-5 md:mt-6">
                <Button
                  title="Download"
                  variant="link"
                  size="link"
                  iconRight={<RxChevronRight />}
                >
                  Download
                </Button>
              </div>
            </div>
          </div>
          <div className="flex flex-col border border-border-primary">
            <div className="flex w-full flex-col items-center justify-center self-start">
              <img
                src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image.svg"
                alt="Relume placeholder image 1"
              />
            </div>
            <div className="flex flex-1 flex-col justify-center p-6 md:p-8">
              <div>
                <p className="mb-2 font-semibold">iOS</p>
                <h2 className="mb-3 text-2xl font-bold md:mb-4 md:text-3xl md:leading-[1.3] lg:text-4xl">
                  iOS app
                </h2>
                <p>
                  Fluid and responsive. Manage your day from anywhere with the
                  same speed and capability.
                </p>
              </div>
              <div className="mt-5 md:mt-6">
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
          <div className="flex flex-col border border-border-primary">
            <div className="flex w-full flex-col items-center justify-center self-start">
              <img
                src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image.svg"
                alt="Relume placeholder image 1"
              />
            </div>
            <div className="flex flex-1 flex-col justify-center p-6 md:p-8">
              <div>
                <p className="mb-2 font-semibold">Web</p>
                <h2 className="mb-3 text-2xl font-bold md:mb-4 md:text-3xl md:leading-[1.3] lg:text-4xl">
                  Web app
                </h2>
                <p>
                  Full power in your browser. No lite version, no compromises,
                  just Todus.
                </p>
              </div>
              <div className="mt-5 md:mt-6">
                <Button
                  title="Download"
                  variant="link"
                  size="link"
                  iconRight={<RxChevronRight />}
                >
                  Download
                </Button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
