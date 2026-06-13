'use client';

import { useCallback, useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { authClient, useSession } from '@/lib/auth-client';
import { SettingsCard } from '@/components/settings/settings-card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSlot,
  InputOTPSeparator,
} from '@/components/ui/input-otp';
import { ShieldCheck, Copy } from 'lucide-react';
import { toast } from 'sonner';

type SetupData = { totpURI: string; backupCodes: string[] };

export function TwoFactorCard() {
  const { data: session } = useSession();
  // Better Auth augments the user with twoFactorEnabled; the inferred Session
  // type doesn't always surface it, so read defensively.
  const sessionEnabled = Boolean((session?.user as { twoFactorEnabled?: boolean })?.twoFactorEnabled);

  const [enabled, setEnabled] = useState(sessionEnabled);
  useEffect(() => setEnabled(sessionEnabled), [sessionEnabled]);

  // Enable flow dialog
  const [enableOpen, setEnableOpen] = useState(false);
  const [step, setStep] = useState<'password' | 'verify'>('password');
  const [password, setPassword] = useState('');
  const [setup, setSetup] = useState<SetupData | null>(null);
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);

  // Disable flow dialog
  const [disableOpen, setDisableOpen] = useState(false);
  const [disablePassword, setDisablePassword] = useState('');

  const resetEnableFlow = useCallback(() => {
    setStep('password');
    setPassword('');
    setSetup(null);
    setQrDataUrl(null);
    setCode('');
    setBusy(false);
  }, []);

  // Render the otpauth URI to a QR data URL whenever setup data arrives.
  useEffect(() => {
    if (!setup?.totpURI) {
      setQrDataUrl(null);
      return;
    }
    QRCode.toDataURL(setup.totpURI, { margin: 1, width: 200 })
      .then(setQrDataUrl)
      .catch(() => setQrDataUrl(null));
  }, [setup?.totpURI]);

  const startEnable = useCallback(async () => {
    if (!password) {
      toast.error('Enter your password to continue.');
      return;
    }
    setBusy(true);
    try {
      const { data, error } = await authClient.twoFactor.enable({ password });
      if (error || !data) {
        toast.error(error?.message || 'Could not start two-factor setup.');
        return;
      }
      setSetup({ totpURI: data.totpURI, backupCodes: data.backupCodes });
      setStep('verify');
    } catch {
      toast.error('Could not start two-factor setup.');
    } finally {
      setBusy(false);
    }
  }, [password]);

  const verifyEnable = useCallback(async () => {
    if (code.length !== 6) {
      toast.error('Enter the 6-digit code from your authenticator app.');
      return;
    }
    setBusy(true);
    try {
      const { error } = await authClient.twoFactor.verifyTotp({ code });
      if (error) {
        toast.error(error.message || 'Invalid code. Try again.');
        return;
      }
      setEnabled(true);
      setEnableOpen(false);
      resetEnableFlow();
      toast.success('Two-factor authentication is on.');
    } catch {
      toast.error('Could not verify the code.');
    } finally {
      setBusy(false);
    }
  }, [code, resetEnableFlow]);

  const disable = useCallback(async () => {
    if (!disablePassword) {
      toast.error('Enter your password to disable two-factor.');
      return;
    }
    setBusy(true);
    try {
      const { error } = await authClient.twoFactor.disable({ password: disablePassword });
      if (error) {
        toast.error(error.message || 'Could not disable two-factor.');
        return;
      }
      setEnabled(false);
      setDisableOpen(false);
      setDisablePassword('');
      toast.success('Two-factor authentication is off.');
    } catch {
      toast.error('Could not disable two-factor.');
    } finally {
      setBusy(false);
    }
  }, [disablePassword]);

  const copyBackupCodes = useCallback(() => {
    if (!setup?.backupCodes?.length) return;
    void navigator.clipboard
      .writeText(setup.backupCodes.join('\n'))
      .then(() => toast.success('Backup codes copied.'))
      .catch(() => toast.error('Could not copy backup codes.'));
  }, [setup?.backupCodes]);

  return (
    <SettingsCard
      title="Two-factor authentication"
      description="Add a TOTP authenticator app (Google Authenticator, 1Password, Authy) as a second step at sign-in."
      action={
        enabled ? (
          <Badge variant="secondary" className="gap-1 text-[11px]">
            <ShieldCheck className="h-3 w-3" /> On
          </Badge>
        ) : undefined
      }
    >
      <div className="flex items-center justify-between gap-3">
        <p className="text-muted-foreground text-[13px]">
          {enabled
            ? 'Your account is protected with an authenticator app.'
            : 'Protect your account with a time-based one-time code.'}
        </p>
        {enabled ? (
          <Button
            variant="outline"
            size="sm"
            className="text-destructive border-destructive/30 hover:bg-destructive/5"
            onClick={() => setDisableOpen(true)}
          >
            Disable
          </Button>
        ) : (
          <Button
            size="sm"
            onClick={() => {
              resetEnableFlow();
              setEnableOpen(true);
            }}
          >
            Enable
          </Button>
        )}
      </div>

      {/* Enable dialog */}
      <Dialog
        open={enableOpen}
        onOpenChange={(open) => {
          setEnableOpen(open);
          if (!open) resetEnableFlow();
        }}
      >
        <DialogContent className="sm:max-w-md">
          {step === 'password' ? (
            <>
              <DialogHeader>
                <DialogTitle>Enable two-factor authentication</DialogTitle>
                <DialogDescription>
                  Confirm your password to generate a setup code.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-2">
                <Label htmlFor="tfa-password">Password</Label>
                <Input
                  id="tfa-password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') void startEnable();
                  }}
                />
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setEnableOpen(false)}>
                  Cancel
                </Button>
                <Button disabled={busy} onClick={() => void startEnable()}>
                  {busy ? 'Working…' : 'Continue'}
                </Button>
              </DialogFooter>
            </>
          ) : (
            <>
              <DialogHeader>
                <DialogTitle>Scan and verify</DialogTitle>
                <DialogDescription>
                  Scan this QR code with your authenticator app, then enter the 6-digit code.
                </DialogDescription>
              </DialogHeader>
              <div className="flex flex-col items-center gap-4">
                {qrDataUrl ? (
                  <img
                    src={qrDataUrl}
                    alt="Two-factor QR code"
                    className="border-border rounded-lg border bg-white p-2"
                    width={200}
                    height={200}
                  />
                ) : (
                  <div className="bg-muted h-[200px] w-[200px] animate-pulse rounded-lg" />
                )}

                <InputOTP maxLength={6} value={code} onChange={setCode}>
                  <InputOTPGroup>
                    <InputOTPSlot index={0} />
                    <InputOTPSlot index={1} />
                    <InputOTPSlot index={2} />
                  </InputOTPGroup>
                  <InputOTPSeparator />
                  <InputOTPGroup>
                    <InputOTPSlot index={3} />
                    <InputOTPSlot index={4} />
                    <InputOTPSlot index={5} />
                  </InputOTPGroup>
                </InputOTP>

                {setup?.backupCodes?.length ? (
                  <div className="w-full">
                    <div className="mb-1.5 flex items-center justify-between">
                      <span className="text-xs font-medium">Backup codes</span>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-7 gap-1 text-[11px]"
                        onClick={copyBackupCodes}
                      >
                        <Copy className="h-3 w-3" /> Copy
                      </Button>
                    </div>
                    <p className="text-muted-foreground mb-2 text-[11px]">
                      Save these somewhere safe. Each code works once if you lose your device.
                    </p>
                    <div className="bg-muted grid grid-cols-2 gap-1 rounded-md p-2 font-mono text-[12px]">
                      {setup.backupCodes.map((c) => (
                        <span key={c}>{c}</span>
                      ))}
                    </div>
                  </div>
                ) : null}
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setEnableOpen(false)}>
                  Cancel
                </Button>
                <Button disabled={busy || code.length !== 6} onClick={() => void verifyEnable()}>
                  {busy ? 'Verifying…' : 'Verify & turn on'}
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>

      {/* Disable dialog */}
      <Dialog
        open={disableOpen}
        onOpenChange={(open) => {
          setDisableOpen(open);
          if (!open) setDisablePassword('');
        }}
      >
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Disable two-factor authentication</DialogTitle>
            <DialogDescription>
              Confirm your password to turn off two-factor. Your account will be less secure.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="tfa-disable-password">Password</Label>
            <Input
              id="tfa-disable-password"
              type="password"
              autoComplete="current-password"
              value={disablePassword}
              onChange={(e) => setDisablePassword(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') void disable();
              }}
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDisableOpen(false)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              disabled={busy}
              onClick={() => void disable()}
            >
              {busy ? 'Working…' : 'Disable'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </SettingsCard>
  );
}
