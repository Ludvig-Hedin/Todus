import { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { useTRPC } from '@/providers/query-provider';
import { useMutation } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Link } from 'react-router';
import { Copy, ExternalLink } from 'lucide-react';

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  conversationId: string;
  conversationTitle: string;
}

type ExpiryOption = 'never' | '1' | '7' | '30';

export function ShareConversationModal({
  open,
  onOpenChange,
  conversationId,
  conversationTitle,
}: Props) {
  const trpc = useTRPC();

  // Form state
  const [title, setTitle] = useState(conversationTitle);
  const [visibility, setVisibility] = useState<'public' | 'protected'>('public');
  const [password, setPassword] = useState('');
  const [expiresInDays, setExpiresInDays] = useState<ExpiryOption>('never');

  // Post-creation state
  const [createdSlug, setCreatedSlug] = useState<string | null>(null);

  const createShare = useMutation(
    trpc.sharing.create.mutationOptions({
      onSuccess: (data) => setCreatedSlug(data.slug),
      onError: () => toast.error('Failed to create share link.'),
    }),
  );

  const shareUrl = createdSlug
    ? `${window.location.origin}/share/${createdSlug}`
    : null;

  const handleCreate = () => {
    createShare.mutate({
      conversationId,
      title,
      password: visibility === 'protected' ? password : undefined,
      expiresInDays,
    });
  };

  const handleCopy = async () => {
    if (!shareUrl) return;
    try {
      await navigator.clipboard.writeText(shareUrl);
      toast.success('Link copied!');
    } catch {
      toast.error('Failed to copy link.');
    }
  };

  // Reset form when dialog closes
  const handleOpenChange = (v: boolean) => {
    if (!v) {
      setCreatedSlug(null);
      setTitle(conversationTitle);
      setVisibility('public');
      setPassword('');
      setExpiresInDays('never');
    }
    onOpenChange(v);
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Share conversation</DialogTitle>
        </DialogHeader>

        {/* ── Creation form ── */}
        {!shareUrl ? (
          <div className="flex flex-col gap-4 pt-1">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="share-title">Title</Label>
              <Input
                id="share-title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Conversation title"
              />
            </div>

            <div className="flex flex-col gap-2">
              <Label>Visibility</Label>
              <RadioGroup
                value={visibility}
                onValueChange={(v) => setVisibility(v as 'public' | 'protected')}
                className="flex flex-col gap-2"
              >
                <div className="flex items-center gap-2">
                  <RadioGroupItem value="public" id="vis-public" />
                  <Label htmlFor="vis-public" className="cursor-pointer font-normal">
                    Public — anyone with the link
                  </Label>
                </div>
                <div className="flex items-center gap-2">
                  <RadioGroupItem value="protected" id="vis-protected" />
                  <Label htmlFor="vis-protected" className="cursor-pointer font-normal">
                    Protected — password required
                  </Label>
                </div>
              </RadioGroup>
            </div>

            {visibility === 'protected' && (
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="share-password">Password</Label>
                <Input
                  id="share-password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Set a password"
                />
              </div>
            )}

            <div className="flex flex-col gap-1.5">
              <Label>Expires</Label>
              <Select
                value={expiresInDays}
                onValueChange={(v) => setExpiresInDays(v as ExpiryOption)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="never">Never</SelectItem>
                  <SelectItem value="1">After 24 hours</SelectItem>
                  <SelectItem value="7">After 7 days</SelectItem>
                  <SelectItem value="30">After 30 days</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <Button
              onClick={handleCreate}
              disabled={
                createShare.isPending ||
                (visibility === 'protected' && !password)
              }
            >
              {createShare.isPending ? 'Creating…' : 'Create link'}
            </Button>
          </div>
        ) : (
          /* ── Success state ── */
          <div className="flex flex-col gap-4 pt-1">
            <p className="text-muted-foreground text-sm">
              {visibility === 'protected'
                ? 'Your share link is ready. A password is required to view it.'
                : 'Your share link is ready. Anyone with this link can view the conversation.'}
            </p>

            <div className="flex items-center gap-2">
              <Input
                readOnly
                value={shareUrl}
                className="font-mono text-xs"
                onClick={(e) => (e.target as HTMLInputElement).select()}
              />
              <Button variant="outline" size="icon" onClick={handleCopy}>
                <Copy className="h-4 w-4" />
                <span className="sr-only">Copy</span>
              </Button>
            </div>

            <div className="flex items-center justify-between">
              <Link
                to="/settings/sharing"
                className="text-muted-foreground flex items-center gap-1 text-sm hover:underline"
              >
                <ExternalLink className="h-3 w-3" />
                Manage shared links
              </Link>
              <Button variant="outline" onClick={() => handleOpenChange(false)}>
                Done
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
