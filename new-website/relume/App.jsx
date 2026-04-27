import { BrowserRouter, Routes, Route } from 'react-router-dom';
import DownloadPage from './download';
import PricingPage from './pricing';
import LegalPage from './legal';
import HomePage from './home';
import React from 'react';

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/download" element={<DownloadPage />} />
        <Route path="/pricing" element={<PricingPage />} />
        <Route path="/legal" element={<LegalPage />} />
      </Routes>
    </BrowserRouter>
  );
}
