'use client';

import { Button } from '@relume_io/relume-ui';

export function Header62() {
  return (
    <section id="relume" className="px-[5%] py-16 md:py-24 lg:py-28">
      <div className="container max-w-lg text-center">
        <p className="mb-3 font-semibold md:mb-4">Transparency</p>
        <h1 className="lg:text-10xl mb-5 text-6xl font-bold md:mb-6 md:text-9xl">Privacy policy</h1>
        <p className="md:text-base">
          Your privacy matters. Here&apos;s how Todus collects, uses, and protects your data.
        </p>
        <div className="mt-6 flex items-center justify-center gap-x-4 md:mt-8">
          <Button title="Read">Read</Button>
          <Button title="Contact" variant="secondary">
            Contact
          </Button>
        </div>
      </div>
    </section>
  );
}
