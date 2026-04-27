"use client";

import { Button } from "@relume_io/relume-ui";
import React from "react";
import { BiCheck } from "react-icons/bi";

export function Pricing10() {
  return (
    <section id="relume" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container max-w-xl">
        <div className="mx-auto mb-12 max-w-lg text-center md:mb-18 lg:mb-20">
          <p className="mb-3 font-semibold md:mb-4">Plans</p>
          <h2 className="rb-5 mb-5 text-5xl font-bold md:mb-6 md:text-7xl lg:text-8xl">
            Pick your plan
          </h2>
          <p className="md:text-md">
            Everything you need to stay organized and focused.
          </p>
        </div>
        <div className="grid grid-cols-1 gap-8 md:grid-cols-2">
          <div className="flex h-full flex-col justify-between border border-border-primary px-6 py-8 md:p-8">
            <div>
              <div className="rb-6 mb-6 text-center md:mb-8">
                <h6 className="text-md font-bold leading-[1.4] md:text-xl">
                  Free
                </h6>
                <h1 className="my-2 text-6xl font-bold md:text-9xl lg:text-10xl">
                  Free
                </h1>
                <p>Forever</p>
              </div>
              <div className="mb-8 grid grid-cols-1 gap-4 py-2">
                <div className="flex self-start">
                  <div className="mr-4 flex-none self-start">
                    <BiCheck className="size-6" />
                  </div>
                  <p>Email and calendar</p>
                </div>
                <div className="flex self-start">
                  <div className="mr-4 flex-none self-start">
                    <BiCheck className="size-6" />
                  </div>
                  <p>Basic task management</p>
                </div>
                <div className="flex self-start">
                  <div className="mr-4 flex-none self-start">
                    <BiCheck className="size-6" />
                  </div>
                  <p>5 GB storage</p>
                </div>
              </div>
            </div>
            <div>
              <Button title="Get started" className="w-full">
                Get started
              </Button>
            </div>
          </div>
          <div className="flex h-full flex-col justify-between border border-border-primary px-6 py-8 md:p-8">
            <div>
              <div className="rb-6 mb-6 text-center md:mb-8">
                <h6 className="text-md font-bold leading-[1.4] md:text-xl">
                  Pro
                </h6>
                <h1 className="my-2 text-6xl font-bold md:text-9xl lg:text-10xl">
                  $9/mo
                </h1>
                <p>or $90 yearly</p>
              </div>
              <div className="mb-8 grid grid-cols-1 gap-4 py-2">
                <div className="flex self-start">
                  <div className="mr-4 flex-none self-start">
                    <BiCheck className="size-6" />
                  </div>
                  <p>Everything in Free</p>
                </div>
                <div className="flex self-start">
                  <div className="mr-4 flex-none self-start">
                    <BiCheck className="size-6" />
                  </div>
                  <p>AI-powered assistant</p>
                </div>
                <div className="flex self-start">
                  <div className="mr-4 flex-none self-start">
                    <BiCheck className="size-6" />
                  </div>
                  <p>Unlimited tasks and notes</p>
                </div>
                <div className="flex self-start">
                  <div className="mr-4 flex-none self-start">
                    <BiCheck className="size-6" />
                  </div>
                  <p>200 GB storage</p>
                </div>
                <div className="flex self-start">
                  <div className="mr-4 flex-none self-start">
                    <BiCheck className="size-6" />
                  </div>
                  <p>Priority support</p>
                </div>
              </div>
            </div>
            <div>
              <Button title="Upgrade now" className="w-full">
                Upgrade now
              </Button>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
