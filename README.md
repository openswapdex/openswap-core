# OpenSwap: Revolutionizing on-chain liquidity

This repository consists of the core smart contracts that includes the following features:

* Governance to configure system parameters including trade fees, protocol fees, adding/modifying price adapters, adding/modifying pairs for Liquidity Queues, etc
* OpenSwap AMM Pools based on Uniswap V2 with modifications to support governance modifications of trade fees and protocol fees.
* OpenSwap Liquidity Queues including the three initial types:
  * Spot Priority Queues where OSWAP staked determines the priority of the liquidity to be executed at spot market price.
  * Spot Range Queues where providers may specify a price range in which their liquidity is active for spot market priced swaps.
  * Restricted Group Queues where providers may configure a whitelist to target their liquidity to specific group of users, ideal for guaranteed buybacks on project tokens or flash sales.
  
For more details on the project, please refer to our [documents.](https://doc.openswap.xyz/)

## Audits

The original set of smart contracts were audited by [CerTiK](https://www.certik.io/) in March 2021 with a second audit completed by [PeckShield](https://peckshield.com/en) on October 25, 2021.

## Bug Bounty

OpenSwap is working on a bug bounty program to be announced soon.
