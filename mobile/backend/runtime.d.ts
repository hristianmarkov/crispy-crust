declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Promise<Response>): void;
  resolveDns(host: string, type: "A" | "AAAA"): Promise<string[]>;
};
