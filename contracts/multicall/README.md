# Multicall

The Multicall contract aggregates results from multiple contract view function calls.

This reduces the number of separate JSON RPC requests that need to be sent while also providing the guarantee that all values returned are from the same block. 