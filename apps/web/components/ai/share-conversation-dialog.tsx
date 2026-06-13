/**
 * Share an AI conversation as a public, read-only link (optionally password-
 * protected, optionally expiring). Mirrors the native ShareConversationSheet.
 * Backend: `sharing.create` (requires the conversation to be saved first).
 */
import { useEffect, useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Check, Copy, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { useTRPC } from '@/providers/query-provider';

type ExpiresInDays = 'never' | '1' | '7' | '30';

interface ShareConversationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  conversationId: string;
  defaultTitle?: string;
}

function appUrl(): string {
  return import.meta.env.VITE_PUBLIC_APP_URL || window.location.origin;
}

export function ShareConversationDialog({
  open,
  onOpenChange,
  conversationId,
  defaultTitle = '',
}: ShareConversationDialogProps) {
  const trpc = useTRPC();
  const [title, setTitle] = useState(defaultTitle);
  const [password, setPassword] = useState('');
  const [expiresInDays, setExpiresInDays] = useState<ExpiresInDays>('never');
  const [shareUrl, setShareUrl] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  // Reset on open.
  useEffect(() => {
    if (open) {
      setTitle(defaultTitle);
      setPassword('');
      setExpiresInDays('never');
      setShareUrl(null);
      setCopied(false);
    }
  }, [open, defaultTitle]);

  const createShare = useMutation({
    ...trpc.sharing.create.mutationOptions(),
    onSuccess: (res) => {
      setShareUrl(`${appUrl()}/share/${res.slug}`);
      toast.success('Share link created');
    },
    onError: (err) => {
      toast.error(
        err instanceof Error && err.message.toLowerCase().includes('not found')
          ? 'Send a message first, then share.'
          : err instanceof Error
            ? err.message
            : 'Could not create share link',
      );
    },
  });

  const handleCreate = () => {
    createShare.mutate({
      conversationId,
      title: title.trim(),
      password: password.trim() || undefined,
      expiresInDays,
    });
  };

  const handleCopy = async () => {
    if (!shareUrl) return;
    try {
      await navigator.clipboard.writeText(shareUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      toast.error('Could not copy link');
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[440px]">
        <DialogHeader>
          <DialogTitle className="text-[15px]">Share conversation</DialogTitle>
          <DialogDescription className="text-[12px]">
            Anyone with the link can view a read-only snapshot of this conversation.
          </DialogDescription>
        </DialogHeader>

        {shareUrl ? (
          <div className="flex flex-col gap-3 py-1">
            <Label className="text-muted-foreground text-[11px]">Public link</Label>
            <div className="flex items-center gap-2">
              <Input readOnly value={shareUrl} aria-label="Share link" className="text-[12px]" />
              <Button size="icon" variant="outline" onClick={handleCopy} aria-label="Copy link">
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
              </Button>
            </div>
          </div>
        ) : (
          <div className="flex flex-col gap-3 py-1">
            <div className="flex flex-col gap-1">
              <Label className="text-muted-foreground text-[11px]">Title (optional)</Label>
              <Input
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Shared conversation"
                aria-label="Share title"
              />
            </div>
            <div className="flex flex-col gap-1">
              <Label className="text-muted-foreground text-[11px]">Password (optional)</Label>
              <Input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="No password"
                aria-label="Share password"
              />
            </div>
            <div className="flex flex-col gap-1">
              <Label className="text-muted-foreground text-[11px]">Expires</Label>
              <Select
                value={expiresInDays}
                onValueChange={(v) => setExpiresInDays(v as ExpiresInDays)}
              >
                <SelectTrigger aria-label="Expiry">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="never">Never</SelectItem>
                  <SelectItem value="1">After 1 day</SelectItem>
                  <SelectItem value="7">After 7 days</SelectItem>
                  <SelectItem value="30">After 30 days</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        )}

        <DialogFooter>
          {shareUrl ? (
            <Button size="sm" onClick={() => onOpenChange(false)}>
              Done
            </Button>
          ) : (
            <>
              <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button size="sm" onClick={handleCreate} disabled={createShare.isPending}>
                {createShare.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  'Create link'
                )}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
