<script lang="ts">
  import * as env from "$env/static/public";
  import { buf2hex } from "$lib/bytes";
  import { createOwners, deployAccount, type ArgentOwners, transferDust, declareAccount } from "$lib/argent";
  import { Account, RpcProvider } from "starknet";

  const rpId = "localhost";
  // const provider = new SequencerProvider({ baseUrl: "http://127.0.0.1:5050" }); // python devnet
  const provider = new RpcProvider({ nodeUrl: env.PUBLIC_PROVIDER_URL });

  let email = "axel@argent.xyz";
  let owners: ArgentOwners | undefined;
  let account: Account | undefined;
  let deployPromise: Promise<void>;
  let sendPromise: Promise<void>;
  let transactionHash = "";

  const handleClickCreateOwners = async () => {
    owners = await createOwners(email, rpId);
  };

  const handleClickDeployWallet = async (classHash: string) => {
    ({ account } = await deployAccount(classHash, owners!, rpId, provider));
  };

  const handleClickSendTransaction = async () => {
    transactionHash = await transferDust(account!, provider);
  };
</script>

<h1>1. Create keys</h1>
{#if !owners}
  <input type="email" bind:value={email} />
  <button on:click={handleClickCreateOwners}>Create</button>
{:else}
  <div>Email: <small>{owners.webauthnOwner.attestation.email}</small></div>
  <div>Stark key: <small>0x{owners.starkOwner.publicKey.toString(16)}</small></div>
  <div>Webauthn public key: <small>{buf2hex(owners.webauthnOwner.attestation.x)}</small></div>
  <div>Webauthn credential id: <small>{buf2hex(owners.webauthnOwner.attestation.credentialId)}</small></div>

  {#await declareAccount(provider)}
    <p>Declaring...</p>
  {:then classHash}
    <p />
    <h1>2. Deploy account</h1>
    <div>Class hash: <small>{classHash}</small></div>
    {#if !account}
      <p />
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
