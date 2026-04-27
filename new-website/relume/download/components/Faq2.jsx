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
            Questions
          </h2>
          <p className="md:text-md">
            Everything you need to know about getting started with Todus.
          </p>
        </div>
        <Accordion type="multiple">
          <AccordionItem value="item-0">
            <AccordionTrigger className="md:py-5 md:text-md">
              How do I install Todus?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Download the app from the App Store for iOS or Mac App Store for
              macOS. On the web, sign in at todus.app. Installation takes
              seconds, and you're ready to work.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-1">
            <AccordionTrigger className="md:py-5 md:text-md">
              What platforms are supported?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Todus runs on macOS, iOS, and the web. The experience is identical
              across all three, so you can switch devices without missing a
              beat.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-2">
            <AccordionTrigger className="md:py-5 md:text-md">
              Do I need an account?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Yes. Sign in with Google, Apple, or email. No passwords to manage,
              and your account is secure from day one.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-3">
            <AccordionTrigger className="md:py-5 md:text-md">
              Is my data private?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Your privacy matters. We use privacy-first authentication and
              never sell your data. Everything stays encrypted and under your
              control.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-4">
            <AccordionTrigger className="md:py-5 md:text-md">
              Can I use it offline?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              The iOS and Mac apps work offline. Changes sync automatically when
              you're back online. The web app requires a connection.
            </AccordionContent>
          </AccordionItem>
        </Accordion>
        <div className="mt-12 md:mt-18 lg:mt-20">
          <h4 className="mb-3 text-2xl font-bold md:mb-4 md:text-3xl md:leading-[1.3] lg:text-4xl">
            Need more help?
          </h4>
          <p className="md:text-md">Reach out to our support team anytime.</p>
          <div className="mt-6 md:mt-8">
            <Button title="Contact" variant="secondary">
              Contact
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}
