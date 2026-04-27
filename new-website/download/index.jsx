import React from 'react';
import { Navbar } from '../src/components/Navbar';
import { Footer } from '../src/components/Footer';
import { Header62 } from './components/Header62';
import { Layout395 } from './components/Layout395';
import { Layout431 } from './components/Layout431';
import { Cta39 } from './components/Cta39';
import { Faq2 } from './components/Faq2';

export default function DownloadPage() {
  return (
    <div className="min-h-screen bg-[var(--background)] text-[var(--foreground)]">
      <Navbar />
      <main>
        <Header62 />
        <Layout395 />
        <Layout431 />
        <Cta39 />
        <Faq2 />
      </main>
      <Footer />
    </div>
  );
}
