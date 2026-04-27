'use client';

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
  Button,
} from '@relume_io/relume-ui';
import React from 'react';

export function Faq2() {
  return (
    <section id="pricing-faq" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container">
        <div className="md:mb-18 mb-12 w-full max-w-lg lg:mb-20">
          <h2 className="mb-5 text-5xl font-bold md:mb-6 md:text-7xl lg:text-8xl">Questions</h2>
          <p className="md:text-base">Everything you need to know about Todus pricing.</p>
        </div>
        <Accordion type="multiple">
          <AccordionItem value="item-0">
            <AccordionTrigger className="md:py-5 md:text-base">
              Do I need a credit card?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              No. The free plan requires nothing but an email address. If you decide to upgrade,
              we'll ask for payment information then.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-1">
            <AccordionTrigger className="md:py-5 md:text-base">
              What happens after my trial?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              There is no trial. Your free plan never expires. When you're ready for more, upgrade
              to Pro and your billing starts immediately.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-2">
            <AccordionTrigger className="md:py-5 md:text-base">
              Can I cancel anytime?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Yes. Cancel your subscription whenever you want. Your data stays with you, and you can
              always come back to the free plan.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-3">
            <AccordionTrigger className="md:py-5 md:text-base">
              Do you offer team plans?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Not yet. Todus is built for individuals right now. We're exploring team features for
              the future based on user feedback.
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="item-4">
            <AccordionTrigger className="md:py-5 md:text-base">
              Can I switch plans?
            </AccordionTrigger>
            <AccordionContent className="md:pb-6">
              Of course. Upgrade or downgrade anytime. Changes take effect immediately, and we'll
              adjust your billing accordingly.
            </AccordionContent>
          </AccordionItem>
        </Accordion>
        <div className="md:mt-18 mt-12 lg:mt-20">
          <h4 className="mb-3 text-2xl font-bold md:mb-4 md:text-3xl md:leading-[1.3] lg:text-4xl">
            Still have questions?
          </h4>
          <p className="md:text-base">Reach out to our support team.</p>
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
