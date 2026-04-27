import React from 'react';
import { Navbar } from '../src/components/Navbar';
import { Footer } from '../src/components/Footer';
import { Header62 } from './components/Header62';
import { Pricing10 } from './components/Pricing10';
import { Pricing26 } from './components/Pricing26';
import { Faq2 } from './components/Faq2';
import { Cta31 } from './components/Cta31';

export default function PricingPage() {
  return (
    <div className="min-h-screen bg-[var(--background)] text-[var(--foreground)]">
      <Navbar />
      <main>
        <Header62 />
        <Pricing10 />
        <Pricing26 />
        <Faq2 />
        <Cta31 />
      </main>
      <Footer />
    </div>
  );
}
