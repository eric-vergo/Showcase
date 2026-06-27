export {};

declare global {
  interface Window {
    VersoBlueprint?: {
      render?: unknown;
      renderReadyCallbacks?: Array<(api: unknown) => void>;
      onRenderReady?: (fn: (api: unknown) => void) => void;
      __private?: Record<string, unknown>;
      slides?: Record<string, unknown>;
    };
    bpTexPreludeTable?: Record<string, string>;
    Reveal?: {
      on?: (event: string, fn: (event: { currentSlide?: Element }) => void) => void;
    };
  }

  const katex: {
    render: (tex: string, element: Element, options?: Record<string, unknown>) => void;
  };
}
