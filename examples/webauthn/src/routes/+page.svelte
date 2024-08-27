<script lang="ts">
  import * as env from "$env/static/public";
  import { buf2hex } from "$lib/bytes";
  import { createOwner, retrieveOwner, cleanLocalStorage, deployAccount, retrieveAccount, transferDust, declareAccount } from "$lib/poc";
  import type { WebauthnOwner} from "$lib/webauthnOwner";
  import { Account, RpcProvider } from "starknet";

  const rpId = "localhost";
  const provider = new RpcProvider({ nodeUrl: env.PUBLIC_PROVIDER_URL });

  let email = "example@argent.xyz";
  let owner: WebauthnOwner | undefined;
  let account: Account | undefined;
  let deployPromise: Promise<void>;
  let sendPromise: Promise<void>;
  let transactionHash = "";

  const handleClickCreateOwner = async () => {
    owner = await createOwner(email, rpId, window.location.origin);
  };

  const retrieveOwnerOnLoad = async () => {
    owner = await retrieveOwner();
  };

  const handleClickDeployWallet = async (classHash: string) => {
    account = await deployAccount(classHash, owner!, provider);
  };

  const retrieveAccountOnLoad = async (classHash: string) => {
    account = await retrieveAccount(classHash, owner!, provider);
  };

  const handleClickSendTransaction = async () => {
    transactionHash = await transferDust(account!, provider);
  };

  const handleCleanLocalStorage = async () => {
    await cleanLocalStorage();
    owner = undefined;
    account = undefined;
  };
</script>

<button on:click={() => (sendPromise = handleCleanLocalStorage())}>Clear local storage</button>
{#await retrieveOwnerOnLoad()}
  <p>Retrieving...</p>
{:then}
  <h1>1. Create keys</h1>
  {#if !owner}
  <input type="email" bind:value={email} />
  <button on:click={handleClickCreateOwner}>Create</button>
  {:else}
    <div>Email: <small>{owner.attestation.email}</small></div>
    <div>Webauthn public key: <small>{buf2hex(owner.attestation.pubKey)}</small></div>
    <div>Webauthn credential id: <small>{buf2hex(owner.attestation.credentialId)}</small></div>

    {#await declareAccount(provider)}
      <p>Declaring...</p>
    {:then classHash}
      <p />
      <h1>2. Deploy account</h1>
      <div>Class hash: <small>{classHash}</small></div>
      {#if !account}
        <p />
        {#await retrieveAccountOnLoad(classHash)}
          <p>Retrieving...</p>
        {/await}
        {#if !deployPromise}
          <button on:click={() => (deployPromise = handleClickDeployWallet(classHash))}>Deploy</button>
        {/if}
        {#await deployPromise}
          <p>Deploying...</p>
        {:catch error}
          <p style="color: red">Couldn't deploy account: {error.message}</p>
        {/await}
      {:else}
        <div>Account address: <small>{account.address}</small></div>
        <h1>3. Send transaction</h1>
        <p>Transfer 1 wei to address 69:</p>
        {#if !transactionHash}
          {#if !sendPromise}
            <button on:click={() => (sendPromise = handleClickSendTransaction())}>Sign & broadcast</button>
          {/if}
          {#await sendPromise}
            <p>Confirming...</p>
          {:catch error}
            <p style="color: red">Couldn't send transaction: {error.message}</p>
          {/await}
        {:else}
          <div>Transaction hash: <small>{transactionHash}</small></div>
        {/if}
      {/if}
    {:catch error}
      <p style="color: red">Couldn't declare account: {error.message}</p>
    {/await}
  {/if}
{/await}

<style>
  :global(body) {
    margin: 0;
    padding-bottom: 50px;
    text-align: center;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", "Fira Sans",
      "Droid Sans", "Helvetica Neue", sans-serif;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
  }
</style>
