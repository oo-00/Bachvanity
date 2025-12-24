# Bachvanity
## Create2 bounty system

Quick 1-day hobby project, not production ready.

User 1 (smart contract dev) creates a paid mining request for an address pattern. Pattern omits 0x prefix. Allowable characters are lowercase hex, and "X" for wildcard.

In this request, the user defines a deadline time no greater than 60 days from now, and the maximum possible points are calculated as 40 minus the count of "X" wildcards. If the request is valid, the order is registered to the contract.

User 2 (salt miner) can submit salt values, which are checked against the request to determine the number of points received. If the submitted salt has a better score than the previous best submission, it will take its place. If the submission scores the maximum number of points, the request payout will reduce to 0 and the user will be paid immediately.

If no user submits a perfect salt, the highest scoring user will be able to claim the bounty after the deadline.