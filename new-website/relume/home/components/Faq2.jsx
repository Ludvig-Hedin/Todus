"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
  Button,
} from "@relume_io/relume-ui";
import React from "react";

export function Faq2() {
  return (
    <section id="relume" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container">
        <div className="rb-12 mb-12 w-full max-w-lg md:mb-18 lg:mb-20">
          <h2 className="rb-5 mb-5 text-5xl font-bold md:mb-6 md:text-7xl lg:text-8xl">
            FAQ
          </h2>
          <p className="md:text-md">Common questions about Todus</p>
        </div>
        <Accordion type="multiple">
          <AccordionItem value="item-0">
            <AccordionTrigger className="md:py-5 md:text-md">
              Is my data private?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Yes. We don't sell your data. Authentication is privacy-first—sign
              in with Google, Apple, or email. All data is encrypted in transit
              and at rest.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-1">
            <AccordionTrigger className="md:py-5 md:text-md">
              What devices are supported?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              iOS, Mac, and web. The apps are native on mobile and Mac for
              speed. The web app has full feature parity—no lite version.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-2">
            <AccordionTrigger className="md:py-5 md:text-md">
              Can I import my email?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Yes. Connect your Gmail account and Todus pulls in your messages,
              calendar, and contacts. Other email providers coming soon.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-3">
            <AccordionTrigger className="md:py-5 md:text-md">
              Is there a free trial?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Yes. Start free with no credit card. Upgrade anytime if you want
              advanced features.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-4">
            <AccordionTrigger className="md:py-5 md:text-md">
              How does the AI work?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              It reads your email, calendar, and tasks to understand your day.
              Then it creates tasks from messages, drafts replies, and suggests
              what to prioritize.
            </AccordionContent>
          </AccordionItem>
        </Accordion>
        <div className="mt-12 md:mt-18 lg:mt-20">
          <h4 className="mb-3 text-2xl font-bold md:mb-4 md:text-3xl md:leading-[1.3] lg:text-4xl">
            Still have questions?
          </h4>
          <p className="md:text-md">Reach out anytime.</p>
          <div className="mt-6 md:mt-8">
            <Button title="Contact us" variant="secondary">
              Contact us
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}
