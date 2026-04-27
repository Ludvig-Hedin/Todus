"use client";

import { Button } from "@relume_io/relume-ui";
import React from "react";
import { RxChevronRight } from "react-icons/rx";

export function Layout469() {
  return (
    <section id="relume" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container">
        <div className="grid grid-cols-1 items-center gap-12 md:grid-cols-2 md:gap-x-16">
          <div>
            <p className="mb-3 font-semibold md:mb-4">Integrated</p>
            <h2 className="mb-5 text-5xl font-bold md:mb-6 md:text-7xl lg:text-8xl">
              An assistant that actually gets things done
            </h2>
            <p className="md:text-md">
              It doesn't just talk. The AI reads your email, creates tasks,
              drafts replies, and organizes your day using what it knows about
              you. Everything works together.
            </p>
            <div className="mt-6 flex flex-wrap gap-4 md:mt-8">
              <Button title="Learn more" variant="secondary">
                Learn more
              </Button>
              <Button
                title="Arrow"
                variant="link"
                size="link"
                iconRight={<RxChevronRight />}
              >
                Arrow
              </Button>
            </div>
          </div>
          <div className="relative flex">
            <div className="absolute left-0 top-[10%] w-1/2">
              <img
                src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image-dim.png"
                className="aspect-square size-full object-cover"
                alt="Relume placeholder image 1"
              />
            </div>
            <div className="ml-[30%]">
              <img
                src="https://d22po4pjz3o32e.cloudfront.net/placeholder-image.svg"
                className="aspect-[2/3] size-full object-cover"
                alt="Relume placeholder image 2"
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
