/**
 * Ollama connection utilities.
 *
 * These run in the browser and talk directly to the user's local Ollama
 * instance. The default Ollama API is at http://localhost:11434.
 *
 * CORS note: Ollama allows localhost origins by default. If the app runs
 * on a different origin (e.g. localhost:5173 for Vite dev), the user
 * must set OLLAMA_ORIGINS="http://localhost:5173" when starting Ollama.
 */

export interface OllamaModel {
  name: string;
  model: string;
  modified_at: string;
  size: number;
  digest: string;
  details: {
    parent_model?: string;
    format?: string;
    family?: string;
    families?: string[];
    parameter_size?: string;
    quantization_level?: string;
  };
}

export interface OllamaPullProgress {
  status: string;
  digest?: string;
  total?: number;
  completed?: number;
  error?: string;
}

const DEFAULT_TIMEOUT_MS = 3000;

/**
 * Check whether an Ollama instance is reachable at the given base URL.
 */
export async function checkOllamaConnection(
  baseUrl: string,
  timeoutMs = DEFAULT_TIMEOUT_MS,
): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    const res = await fetch(`${baseUrl}/api/tags`, { signal: controller.signal });
    clearTimeout(timeout);
    return res.ok;
  } catch {
    return false;
  }
}

/**
 * Fetch the list of installed Ollama models.
 */
export async function fetchOllamaModels(baseUrl: string): Promise<OllamaModel[]> {
  const res = await fetch(`${baseUrl}/api/tags`);
  if (!res.ok) {
    throw new Error(`Ollama unreachable at ${baseUrl} (status ${res.status})`);
  }
  const data = (await res.json()) as { models?: OllamaModel[] };
  return data.models ?? [];
}

/**
 * Pull (download) a model from the Ollama registry.
 * Streams progress updates via a callback.
 */
export async function pullOllamaModel(
  baseUrl: string,
  modelName: string,
  onProgress?: (progress: OllamaPullProgress) => void,
): Promise<void> {
  const res = await fetch(`${baseUrl}/api/pull`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: modelName }),
  });

  if (!res.ok) {
    throw new Error(`Failed to pull model "${modelName}" (status ${res.status})`);
  }

  // Ollama streams progress as newline-delimited JSON
  const reader = res.body?.getReader();
  if (!reader) return;

  const decoder = new TextDecoder();
  let buffer = '';
  const handleProgressLine = (line: string) => {
    if (!line.trim()) return;
    try {
      const progress = JSON.parse(line) as OllamaPullProgress;
      if (typeof progress.error === 'string' && progress.error.trim()) {
        throw new Error(progress.error);
      }
      onProgress?.(progress);
    } catch (error) {
      if (error instanceof SyntaxError) {
        // Skip malformed lines
        return;
      }
      throw error;
    }
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      handleProgressLine(buffer);
      break;
    }

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() ?? ''; // Keep incomplete line in buffer

    for (const line of lines) {
      handleProgressLine(line);
    }
  }
}

/**
 * Delete an installed Ollama model.
 */
export async function deleteOllamaModel(baseUrl: string, modelName: string): Promise<void> {
  const res = await fetch(`${baseUrl}/api/delete`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: modelName }),
  });

  if (!res.ok) {
    throw new Error(`Failed to delete model "${modelName}" (status ${res.status})`);
  }
}

/**
 * Format a model size in bytes to a human-readable string (e.g. "4.2 GB").
 */
export function formatModelSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

/**
 * CORS troubleshooting message shown when Ollama is unreachable.
 */
export const OLLAMA_CORS_HELP = `Ollama may need CORS configuration to allow browser requests.

Run Ollama with:
  OLLAMA_ORIGINS="*" ollama serve

Or restrict to your dev origin:
  OLLAMA_ORIGINS="http://localhost:5173" ollama serve`;
