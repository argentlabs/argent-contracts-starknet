import { BackendService, IncompleteOffChainSession } from "./";

export class ArgentX {
  constructor(
    public address: string,
    public backendService: BackendService,
  ) {}

  public sendSessionInitiationToBackend(session: IncompleteOffChainSession): bigint {
    return this.backendService.givePublicKeyForSession(session);
  }
}
