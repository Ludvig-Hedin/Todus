import React from 'react';
import { Navbar } from '../src/components/Navbar';
import { Footer } from '../src/components/Footer';
import { Header62 } from './components/Header62';
import { Content27 } from './components/Content27';

export default function LegalPage() {
  return (
    <div className="min-h-screen bg-[var(--background)] text-[var(--foreground)]">
      <Navbar />
      <main>
        <Header62 />
        <Content27 />
      </main>
      <Footer />
    </div>
  );
}
