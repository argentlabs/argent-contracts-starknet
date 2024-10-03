TODO remove file when we settle this

Storage use cases:

Model:
A: single list
B: single linked list
C: list per type
D: linked list per type

- deployment: low storage  
  A: N*1 best, N*2 worst, no hashing
  B: N*1 best, N*2 worst, some hashing
  C: N*1 best, N*1 worst, no hashing
  D: N*1 best, N*1 worst, some hashing

- sig validation: check if given Signer is an owner
  A: 2 reads best, N+1 reads average, 2N reads worst, (alternative sig change to include index)
  B: 2 reads always
  C: less reads than A as we can jump to right type
  D: 2 reads always

- legacy signature, quickly find single owner of type Starknet
  A: 1 read min, 3 read safer (ensure single owner)
  B: 1 read min, 3 read + hashing safer (ensure single owner)
  C: 1 read min, T+1 reads safer (ensure single owner)
  C: 1 read min, T+1 reads safer (ensure single owner)

- check if single owner (how important is it?)
  A: 2 read
  B: 2 read
  C: T+1 reads
  D: T+1 reads

- retrieve owners data: read type and pubkey
  A: (2N)+1 reads
  B: (2N)+1 reads + hashing
  C: 2N+T reads
  D: 2N+T reads + hashing

- change (single) owner:
- add owner: check if existing
- remove_owner:
- replace owner:
