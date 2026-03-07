import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '../ui/dialog';
import { useConnections } from '@/hooks/use-connections';
import { emailProviders } from '@/lib/constants';
import { authClient } from '@/lib/auth-client';
import { m } from '@/paraglide/messages';
import { motion } from 'motion/react';
import { Button } from '../ui/button';
import { useLocation } from 'react-router';

export const ConnectionWrapper = () => {
    const { data: connectionsData, isLoading } = useConnections();
    const location = useLocation();

    // We only show this if we have finished loading and confirmed there are 0 connections
    const hasNoConnections = connectionsData && connectionsData.connections.length === 0;

    if (isLoading || !hasNoConnections) return null;

    return (
        <Dialog open={true}>
            <DialogContent
                showOverlay={false}
                className="max-w-md border-none bg-transparent shadow-none"
                onPointerDownOutside={(e) => e.preventDefault()}
                onEscapeKeyDown={(e) => e.preventDefault()}
            >
                <div className="bg-panelLight dark:bg-panelDark rounded-xl border p-6 shadow-2xl">
                    <DialogHeader>
                        <DialogTitle className="text-xl">{m['pages.settings.connections.connectEmail']()}</DialogTitle>
                        <DialogDescription className="mt-2 text-[13px] leading-relaxed">
                            {m['pages.settings.connections.connectEmailDescription']()}
                        </DialogDescription>
                    </DialogHeader>

                    <motion.div
                        className="mt-6 grid grid-cols-2 gap-4"
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        transition={{ duration: 0.3 }}
                    >
                        {emailProviders.map((provider, index) => {
                            const Icon = provider.icon;
                            return (
                                <motion.div
                                    key={provider.name}
                                    initial={{ opacity: 0, y: 20 }}
                                    animate={{ opacity: 1, y: 0 }}
                                    transition={{ delay: index * 0.1, duration: 0.3 }}
                                    whileHover={{ scale: 1.02 }}
                                    whileTap={{ scale: 0.98 }}
                                >
                                    <Button
                                        variant="outline"
                                        className="h-28 w-full flex-col items-center justify-center gap-3 border shadow-sm"
                                        onClick={async () =>
                                            await authClient.linkSocial({
                                                provider: provider.providerId,
                                                callbackURL: `${window.location.origin}${location.pathname}`,
                                            })
                                        }
                                    >
                                        <Icon className="size-7!" />
                                        <span className="text-[13px] font-medium">{provider.name}</span>
                                    </Button>
                                </motion.div>
                            );
                        })}
                    </motion.div>
                </div>
            </DialogContent>
        </Dialog>
    );
};
