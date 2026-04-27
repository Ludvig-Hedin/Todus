import React from 'react';
import { Navbar } from '../src/components/Navbar';
import { HeroSection } from '../src/components/HeroSection';
import { FeaturesSection } from '../src/components/FeaturesSection';
import { AssistantSection } from '../src/components/AssistantSection';
import { WhySection } from '../src/components/WhySection';
import { CTASection } from '../src/components/CTASection';
import { FAQSection } from '../src/components/FAQSection';
import { Footer } from '../src/components/Footer';

export default function HomePage() {
  return (
    <div className="min-h-screen bg-[var(--background)] text-[var(--foreground)]">
      <Navbar />
      <main>
        <HeroSection />
        <div className="h-px w-full bg-[var(--border)]" />
        <FeaturesSection />
        <div className="h-px w-full bg-[var(--border)]" />
        <AssistantSection />
        <div className="h-px w-full bg-[var(--border)]" />
        <WhySection />
        <div className="h-px w-full bg-[var(--border)]" />
        <CTASection />
        <div className="h-px w-full bg-[var(--border)]" />
        <FAQSection />
      </main>
      <Footer />
    </div>
  );
}
