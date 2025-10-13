<script lang="ts">
  import * as env from "$env/static/public";
  import { onMount } from "svelte";
  import { buf2hex } from "$lib/bytes";
  import {
    createOwner,
    cleanLocalStorage,
    printLocalStorage,
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

  let email = "example@ready.co";
  let pubKey = "";
  let classHash = "";
  let recipient = "0x69";
  let owner: WebauthnOwner | undefined;
  let account: Account | undefined;
  let deployPromise: Promise<void> | undefined;
  let sendPromise: Promise<void> | undefined;
  let transactionHash = "";
  let result = "";

  const handleClickCreateOwner = async () => {
    const localOwner = await createOwner(email, rpId, window.location.origin);    
    // For some reason need to wait for 1password to work
    await setTimeout(() =>  owner = localOwner, 400);
  };

  const handleClickReuseOwner = async () => {
    owner = await retrievePasskey(email,rpId, origin, pubKey);
  };

  const handleClassHash = async () => {
    try {
    classHash = await declareAccount(provider);
    } catch (error) {
      console.log(error);
      throw error;
    }
  };

  // https://www.reddit.com/r/Passkeys/comments/1aov4m6/whats_the_point_of_google_chrome_creating_synced/
  const handleClickDeployWallet = async (classHash: string) => {
    account = await deployAccount(classHash, owner!, provider);
  };

  const retrieveAccountOnLoad = async (classHash: string) => {
    account = await retrieveAccount(classHash, owner!, provider);
  };

  const handleClickSendTransaction = async () => {
    transactionHash = await transferDust(account!, provider, recipient);
    let {statusReceipt} = await provider.getTransactionReceipt(transactionHash);
    result = statusReceipt;
  };

  const handleRestart = () => {
    owner = undefined;
    account = undefined;
    transactionHash = "";
    deployPromise = undefined;
    sendPromise = undefined;
    email = "example@ready.co";
  };

  const handleCleanLocalStorage = async () => {
    await cleanLocalStorage();
    handleRestart();
  };
</script>

<svelte:head>
  <title>Ready WebAuthn Demo</title>
</svelte:head>

<div class="min-h-screen bg-gradient-to-b from-orange-50 to-white">
  <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="bg-white rounded-xl shadow-lg p-8 mb-8">
      <h1 class="text-3xl font-bold text-orange-600 mb-6">Ready WebAuthn Demo</h1>
      
      <div class="space-y-4 mb-8">
        <h2 class="text-xl font-semibold text-gray-700 mb-4">Debug Tools</h2>
        <div class="flex flex-wrap gap-4">
          <button on:click={handleCleanLocalStorage} type="button" 
            class="bg-white hover:bg-orange-500 text-orange-600 font-medium hover:text-white py-2 px-6 border-2 border-orange-500 hover:border-transparent rounded-lg transition-all duration-200 shadow-sm hover:shadow cursor-pointer">
            Clean local storage
          </button>
          <button on:click={printLocalStorage} type="button" 
            class="bg-white hover:bg-orange-500 text-orange-600 font-medium hover:text-white py-2 px-6 border-2 border-orange-500 hover:border-transparent rounded-lg transition-all duration-200 shadow-sm hover:shadow cursor-pointer">
            Print local storage
          </button>
          <button on:click={handleRestart} type="button" 
            class="bg-white hover:bg-orange-500 text-orange-600 font-medium hover:text-white py-2 px-6 border-2 border-orange-500 hover:border-transparent rounded-lg transition-all duration-200 shadow-sm hover:shadow cursor-pointer">
            Restart
          </button>
        </div>
      </div>

      <div class="border-t border-gray-200 pt-4">
        <h2 class="text-2xl font-bold text-gray-800 mb-6">1. Create keys</h2>

        {#if !owner}
          <form class="space-y-6">
            <div class="space-y-2">
              <label for="email" class="block text-sm font-medium text-gray-700">Email address</label>
              <div class="w-full max-w-sm">
                <input 
                  id="email"
                  type="email"
                  class="w-full bg-white placeholder:text-gray-400 text-gray-900 text-sm border border-gray-300 rounded-lg px-4 py-2.5 transition duration-200 ease-in-out focus:border-orange-500 focus:ring-2 focus:ring-orange-200 hover:border-orange-300 shadow-sm" 
                  placeholder="Enter your email" 
                  bind:value={email} 
                  required
                >
              </div>
            </div>

            <div class="space-y-2">
              <label for="pubkey" class="block text-sm font-medium text-gray-700">Public Key (optional)</label>
              <div class="w-full max-w-sm">
                <input 
                  id="pubkey"
                  class="w-full bg-white placeholder:text-gray-400 text-gray-900 text-sm border border-gray-300 rounded-lg px-4 py-2.5 transition duration-200 ease-in-out focus:border-orange-500 focus:ring-2 focus:ring-orange-200 hover:border-orange-300 shadow-sm" 
                  placeholder="Enter public key" 
                  bind:value={pubKey}
                >
              </div>
            </div>

            <div class="flex gap-4 pt-2">
              <div class="relative group">
                <button 
                  on:click={handleClickReuseOwner}
                  type="button"
                  class="bg-white hover:bg-orange-500 text-orange-600 font-medium hover:text-white py-2.5 px-6 border-2 border-orange-500 hover:border-transparent rounded-lg transition-all duration-200 shadow-sm hover:shadow cursor-pointer disabled:bg-gray-100 disabled:text-gray-400 disabled:border-gray-300 disabled:cursor-not-allowed disabled:hover:bg-gray-100 disabled:hover:text-gray-400 disabled:hover:border-gray-300"
                  disabled={!email || !pubKey}
                  aria-describedby="tooltip-reuse"
                >
                  Re-use passkey
                </button>
                {#if !email || !pubKey}
                  <div 
                    id="tooltip-reuse"
                    class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-3 py-2 bg-gray-900 text-white text-sm rounded shadow-lg opacity-0 group-hover:opacity-100 transition-opacity duration-200 whitespace-nowrap"
                  >
                    {!email && !pubKey ? 'Please fill in email and public key' : !email ? 'Please fill in email' : 'Please fill in public key'}
                    <div class="absolute top-full left-1/2 transform -translate-x-1/2 -mt-1">
                      <div class="border-4 border-transparent border-t-gray-900"></div>
                    </div>
                  </div>
                {/if}
              </div>
              <button 
                on:click={handleClickCreateOwner}
                  class="bg-orange-500 hover:bg-orange-600 text-white font-medium py-2.5 px-6 border-2 border-orange-500 hover:border-transparent rounded-lg transition-all duration-200 shadow-sm hover:shadow cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-orange-500 disabled:hover:border-orange-500"
                  disabled={!email}
              >
                Register
              </button>
            </div>
          </form>
        {:else}
          <div class="space-y-6">
            <div class="bg-orange-50 rounded-lg p-6 space-y-4">
              <div class="space-y-1">
                <label for="owner-email" class="text-sm font-medium text-gray-700">Email</label>
                <div id="owner-email" class="text-sm text-gray-900">{owner.attestation.email}</div>
              </div>
              
              <div class="space-y-1">
                <label for="owner-pubkey" class="text-sm font-medium text-gray-700">Webauthn public key</label>
                <div id="owner-pubkey" class="text-sm text-gray-900 break-all font-mono bg-white p-2 rounded border border-orange-200">
                  {buf2hex(owner.attestation.pubKey)}
                </div>
              </div>
              
              <div class="space-y-1">
                <label for="owner-credential" class="text-sm font-medium text-gray-700">Webauthn credential ID</label>
                <div id="owner-credential" class="text-sm text-gray-900 break-all font-mono bg-white p-2 rounded border border-orange-200">
                  {buf2hex(owner.attestation.credentialId)}
                </div>
              </div>
            </div>

            {#if !classHash}
              {#await handleClassHash()}
                <div class="flex items-center justify-center py-4">
                  <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-orange-500"></div>
                  <span class="ml-3 text-gray-700">Declaring...</span>
                </div>
              {:catch error}
                <div class="bg-red-50 border-l-4 border-red-500 p-4 my-4">
                  <div class="flex">
                    <div class="ml-3">
                      <p class="text-sm text-red-700">
                        Couldn't declare account: {error.message}
                      </p>
                    </div>
                  </div>
                </div>
              {/await}
            {:else}
              <div class="border-t border-gray-200 pt-4">
                <h2 class="text-2xl font-bold text-gray-800 mb-6">2. Deploy account</h2>
                <div class="space-y-1">
                  <label for="class-hash" class="text-sm font-medium text-gray-700">Class hash</label>
                  <div id="class-hash" class="text-sm text-gray-900 break-all font-mono bg-orange-50 p-2 rounded border border-orange-200">
                    {classHash}
                  </div>
                </div>

                {#if !account}
                  {#await retrieveAccountOnLoad(classHash)}
                    <div class="flex items-center justify-center py-4">
                      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-orange-500"></div>
                      <span class="ml-3 text-gray-700">Retrieving account...</span>
                    </div>
                  {/await}
                  {#if !deployPromise}
                    <div class="mt-6">
                      <button 
                        on:click={() => (deployPromise = handleClickDeployWallet(classHash))}
                        class="bg-orange-500 hover:bg-orange-600 text-white font-medium py-2.5 px-6 border-2 border-orange-500 hover:border-transparent rounded-lg transition-all duration-200 shadow-sm hover:shadow cursor-pointer"
                      >
                        Deploy Account
                      </button>
                    </div>
                  {/if}
                  {#await deployPromise}
                    <div class="flex items-center justify-center py-4">
                      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-orange-500"></div>
                      <span class="ml-3 text-gray-700">Deploying account...</span>
                    </div>
                  {/await}
                {:else}
                  <div class="space-y-1 mt-4">
                    <label for="account-address" class="text-sm font-medium text-gray-700">Account address</label>
                    <div id="account-address" class="text-sm text-gray-900 break-all font-mono bg-orange-50 p-2 rounded border border-orange-200">
                      {account.address}
                    </div>
                  </div>

                  <div class="border-t border-gray-200 pt-4 mt-8">
                    <h2 class="text-2xl font-bold text-gray-800 mb-6">3. Send transaction</h2>
                    
                    <div class="space-y-6">
                      <div class="space-y-2">
                        <label for="recipient" class="block text-sm font-medium text-gray-700">
                          Transfer 1 fri to address:
                        </label>
                        <div class="w-full max-w-sm">
                          <input 
                            id="recipient"
                            bind:value={recipient} 
                            class="w-full bg-white placeholder:text-gray-400 text-gray-900 text-sm border border-gray-300 rounded-lg px-4 py-2.5 transition duration-200 ease-in-out focus:border-orange-500 focus:ring-2 focus:ring-orange-200 hover:border-orange-300 shadow-sm"
                            placeholder="Enter recipient address"
                          >
                        </div>
                      </div>

                      {#if !transactionHash}
                        {#if !sendPromise}
                          <button 
                            on:click={() => (sendPromise = handleClickSendTransaction())}
                            class="bg-orange-500 hover:bg-orange-600 text-white font-medium py-2.5 px-6 border-2 border-orange-500 hover:border-transparent rounded-lg transition-all duration-200 shadow-sm hover:shadow cursor-pointer"
                          >
                            Send Transaction
                          </button>
                        {/if}
                        {#await sendPromise}
                          <div class="flex items-center justify-center py-4">
                            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-orange-500"></div>
                            <span class="ml-3 text-gray-700">Confirming transaction...</span>
                          </div>
                        {:catch error}
                          <div class="bg-red-50 border-l-4 border-red-500 p-4">
                            <div class="flex">
                              <div class="ml-3">
                                <p class="text-sm text-red-700">
                                  Couldn't send transaction: {error.message}
                                </p>
                              </div>
                            </div>
                          </div>
                        {/await}
                      {:else}
                        <div class="space-y-1">
                          <label for="tx-hash" class="text-sm font-medium text-gray-700">Transaction hash</label>
                          <div id="tx-hash" class="text-sm text-gray-900 break-all font-mono bg-orange-50 p-2 rounded border border-orange-200">
                            {transactionHash} Status: {result || "Pending"}
                          </div>
                        </div>
                      {/if}
                    </div>
                  </div>
                {/if}
              </div>
            {/if}
          </div>
        {/if}
      </div>
    </div>
  </div>
</div>