<script lang="ts">
  import * as env from "$env/static/public";
  import { onMount } from "svelte";
  import { buf2hex } from "$lib/bytes";
  import {
    createOwner,
    retrieveOwner,
    cleanLocalStorage,
    deployAccount,
    retrievePasskey,
    retrieveAccount,
    transferDust,
    declareAccount,
  } from "$lib/poc";
  import type { WebauthnOwner } from "$lib/webauthnOwner";
  import { Account, RpcProvider } from "starknet";

  let rpId = "";
  onMount(() => (rpId = window.location.hostname));
  const provider = new RpcProvider({ nodeUrl: env.PUBLIC_PROVIDER_URL });

  let email = "example@argent.xyz";
  let pubKey = "";
  let recipient = "0x69";
  let owner: WebauthnOwner | undefined;
  let account: Account | undefined;
  let deployPromise: Promise<void> | undefined;
  let sendPromise: Promise<void> | undefined;
  let transactionHash = "";

  const handleClickCreateOwner = async () => {
    await createOwner(email, rpId, window.location.origin);
    await retrieveOwnerOnLoad();
  };

  const handleClickReuseOwner = async () => {
    owner = await retrievePasskey(email, rpId, window.location.origin, pubKey);
  };

  // https://www.reddit.com/r/Passkeys/comments/1aov4m6/whats_the_point_of_google_chrome_creating_synced/
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
    transactionHash = "";
    deployPromise = undefined;
    sendPromise = undefined;
  };
</script>

<div class="centered-element">
  {#await retrieveOwnerOnLoad()}
    <p>Retrieving...</p>
  {:then}
    <h1>1. Create keys</h1>
    {#if !owner}
      <input type="text" bind:value={pubKey} autocomplete="email webauthn" />
      <button on:click={handleClickReuseOwner}>Re-use passkey</button>
      <br />
      <br />
      <form>
        <input type="text" bind:value={email} />
        <button on:click={handleClickCreateOwner} type="submit">Register</button>
      </form>
    {:else}
      <button on:click={handleCleanLocalStorage}>Remove account</button>
      <br />
      <br />
      <div>Email: <small>{owner.attestation.email}</small></div>
      <div>
        Webauthn public key: <small>{buf2hex(owner.attestation.pubKey)}</small>
      </div>
      <div>
        Webauthn credential id: <small>{buf2hex(owner.attestation.credentialId)}</small>
      </div>

      <!-- TODO SHOULD DECLARE TOP LEVEL -->
      <!-- This is blocking and can be annoying, fix would be to send it to a web worker to avoid that -->
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
          <p>Transfer 1 wei to address {recipient}:</p>
          <input type="text" bind:value={recipient} />
          <br />
          <br />
          {#if !transactionHash}
            {#if !sendPromise}
              <button on:click={() => (sendPromise = handleClickSendTransaction())}>Send</button>
            {/if}
            {#await sendPromise}
              <p>Confirming...</p>
            {:catch error}
              <p style="color: red">
                Couldn't send transaction: {error.message}
              </p>
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
</div>

<style>
  :global(body) {
    text-align: left;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", "Fira Sans",
      "Droid Sans", "Helvetica Neue", sans-serif;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
  }

  .centered-element {
    margin-left: auto;
    margin-right: auto;
    padding: 15px;
    width: 700px;
  }
</style>
