import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ExternalLink, Loader2 } from 'lucide-react';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useToast } from '@/components/ui/use-toast';
import { apiClient } from '@/lib/api/client';
import { SettingRow, SettingSection } from '../ServerTab/SettingRow';

export function FishAudioSection() {
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [apiKey, setApiKey] = useState('');

  const { data: status, isLoading } = useQuery({
    queryKey: ['fish-audio-settings'],
    queryFn: () => apiClient.getFishAudioSettings(),
  });

  const configured = status?.configured ?? false;

  const saveKey = useMutation({
    mutationFn: () => apiClient.updateFishAudioSettings({ api_key: apiKey.trim() }),
    onSuccess: () => {
      setApiKey('');
      queryClient.invalidateQueries({ queryKey: ['fish-audio-settings'] });
      queryClient.invalidateQueries({ queryKey: ['model-status'] });
      toast({
        title: 'Fish Audio API key saved',
        description: 'Cloud TTS models are now available.',
      });
    },
    onError: (error: Error) =>
      toast({
        title: 'Could not save API key',
        description: error.message,
        variant: 'destructive',
      }),
  });

  const verifyKey = useMutation({
    mutationFn: () =>
      apiClient.verifyFishAudioKey(
        apiKey.trim() ? { api_key: apiKey.trim() } : undefined,
      ),
    onSuccess: (result) =>
      toast({
        title: 'Fish Audio key verified',
        description:
          result.credit != null
            ? `Authentication successful. Credits: ${result.credit}`
            : 'Authentication successful.',
      }),
    onError: (error: Error) =>
      toast({
        title: 'Verification failed',
        description: error.message,
        variant: 'destructive',
      }),
  });

  const disconnect = useMutation({
    mutationFn: () => apiClient.clearFishAudioSettings(),
    onSuccess: () => {
      setApiKey('');
      queryClient.invalidateQueries({ queryKey: ['fish-audio-settings'] });
      queryClient.invalidateQueries({ queryKey: ['model-status'] });
      toast({
        title: 'Fish Audio disconnected',
        description: 'The stored API key was removed from this device.',
      });
    },
    onError: (error: Error) =>
      toast({
        title: 'Could not disconnect',
        description: error.message,
        variant: 'destructive',
      }),
  });

  const busy = saveKey.isPending || verifyKey.isPending || disconnect.isPending;

  return (
    <SettingSection
      title="Fish Audio"
      description="Cloud TTS with voice cloning. Requires a Fish Audio API key — no local model download."
    >
      <SettingRow
        title={configured ? 'Connected' : 'API Key'}
        description={
          configured
            ? `Key configured${status?.key_prefix ? ` · ${status.key_prefix}…` : ''}${
                status?.source === 'environment' ? ' (from environment)' : ''
              }`
            : 'Get a key from fish.audio and paste it here to enable cloud TTS.'
        }
        action={
          configured ? (
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                disabled={busy}
                onClick={() => verifyKey.mutate()}
              >
                {verifyKey.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  'Verify'
                )}
              </Button>
              <Button
                variant="ghost"
                size="sm"
                disabled={busy}
                onClick={() => disconnect.mutate()}
              >
                Remove key
              </Button>
            </div>
          ) : (
            <Button variant="outline" size="sm" asChild>
              <a href={status?.api_keys_url ?? 'https://fish.audio/app/api-keys'} target="_blank" rel="noreferrer">
                Get API key
                <ExternalLink className="h-3.5 w-3.5 ml-1" />
              </a>
            </Button>
          )
        }
      >
        {!configured && (
          <div className="flex gap-2 pt-1">
            <Input
              type="password"
              placeholder="Paste Fish Audio API key"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              disabled={busy || isLoading}
              autoComplete="off"
            />
            <Button
              size="sm"
              disabled={busy || !apiKey.trim()}
              onClick={() => saveKey.mutate()}
            >
              {saveKey.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Save'}
            </Button>
          </div>
        )}
        {configured && (
          <div className="flex gap-2 pt-1">
            <Input
              type="password"
              placeholder="Replace with a new API key"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              disabled={busy}
              autoComplete="off"
            />
            <Button
              size="sm"
              variant="outline"
              disabled={busy || !apiKey.trim()}
              onClick={() => saveKey.mutate()}
            >
              Update
            </Button>
          </div>
        )}
      </SettingRow>
    </SettingSection>
  );
}
