'use client';

import { useEffect } from 'react';

declare global {
    interface Window {
        $crisp: any[];
        CRISP_WEBSITE_ID: string;
    }
}

export function CrispWidget() {
    useEffect(() => {
        // Initialize Crisp
        window.$crisp = [];
        window.CRISP_WEBSITE_ID = '8bfa3b38-0983-4996-985a-0d54f7560908';

        const script = document.createElement('script');
        script.src = 'https://client.crisp.chat/l.js';
        script.async = true;
        document.head.appendChild(script);

        // Cleanup function to remove the widget when navigating away
        return () => {
            // Crisp doesn't have a formal "unload" but we can hide it or let it persist
            // for informational pages. Since this component is only in the (full-width) layout,
            // it will mount/unmount accordingly.
            if (window.$crisp) {
                // We can use Crisp API to hide it if needed
                // window.$crisp.push(['do', 'chat:hide']);
            }
        };
    }, []);

    return null;
}
