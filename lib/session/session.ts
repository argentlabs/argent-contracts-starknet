import { ArraySignatureType, typedData } from "starknet";
import {
  AllowedMethod,
  ArgentAccount,
  ArgentX,
  BackendService,
  DappService,
  Session,
  StarknetKeyPair,
  randomStarknetKeyPair,
} from "..";

interface SessionSetup {
  accountWithDappSigner: ArgentAccount;
  sessionHash: string;
  sessionRequest: Session;
  authorizationSignature: ArraySignatureType;
  backendService: BackendService;
  dappService: DappService;
  argentX: ArgentX;
}
export async function setupSession(
  guardian: StarknetKeyPair,
  account: ArgentAccount,
  allowedMethods: AllowedMethod[],
  expiry: bigint = BigInt(Date.now()) + 10000n,
  dappKey: StarknetKeyPair = randomStarknetKeyPair(),
  cacheOwnerGuid = 0n,
  isLegacyAccount = false,
): Promise<SessionSetup> {
  const backendService = new BackendService(guardian);
  const dappService = new DappService(backendService, dappKey);
  const argentX = new ArgentX(account, backendService);

  const sessionRequest = dappService.createSessionRequest(allowedMethods, expiry);

  const sessionTypedData = await sessionRequest.getTypedData();
  const authorizationSignature = await argentX.getOffchainSignature(sessionTypedData);
  return {
    accountWithDappSigner: dappService.getAccountWithSessionSigner(
      account,
      sessionRequest,
      authorizationSignature,
      cacheOwnerGuid,
      isLegacyAccount,
    ),
    sessionHash: typedData.getMessageHash(sessionTypedData, account.address),
    sessionRequest,
    authorizationSignature,
    backendService,
    dappService,
    argentX,
  };
}
