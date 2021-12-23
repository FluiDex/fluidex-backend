# FluiDex Backend

FluiDex team is building the first permissionless layer2 orderbook DEX on Ethereum, powered by PLONK zk-rollup.

This repo contains all the backend stuff, including exchange matching engine, rollup state manager, prover cluster (master and workers), and zk circuit codes. You can read through our design rationale [here](https://www.fluidex.io/en/blog/fluidex-architecture/).

Currently it is only a demo/PoC version, and many features are still WIP. 

# Architecture

<p align="center">
  <img src="docs/FluiDex Architecture.svg" width="600" >
</p>

# Components & Submodules

Submodules:

* circuits: ZK-Rollup circuits written in circom. It lies in the rollup-state-manager submodule.
* dingir-exchange: the matching engine server. It matches eddsa-signed L2 orders from users, and generates trades. It writes all the 'events' (e.g., orders/trades/balance updates) to the global Kafka message bus.
* rollup-state-manager: maintaining the global rollup state Merkle tree. It fetches events/transactions from the Kafka message bus, and updates the Merkle tree accordingly, and generates L2 blocks.
* prover-cluster: a master-workers cluster for proving PLONK ZK-SNARK circuits. It loads L2 blocks generated by rollup-state-manager, then proves them, and writes the proofs to databases.
* regnbue-bridge: a L1-L2 bridge for fast withdrawal/deposit. Currently in the demo version, it acts like a faucet, sending some initial tokens to each new user of the FluiDex zk-rollup network.

Some external services:

* Kafka: used as the global message bus.
* PostgreSQL: the main database we use. It stores the match engine history/state, prover-cluster state, rollup (L2 blocks/L2 txs) state etc. 
* TimescaleDB: time-series databases, used for exchange market data (e.g., K-Line).

Some zero knowledge development tools developed by Fludiex team are used to process the circuits, including [snarkit](https://github.com/fluidex/snarkit) and [plonkit](https://github.com/fluidex/plonkit)


# How to run it

Ubuntu 20.04 is the only supported environment currently. You could speed up the building following https://doc.rust-lang.org/cargo/guide/build-cache.html#shared-cache, and more documents can be found [here](https://github.com/mozilla/sccache/blob/master/README.md).

```
# install some dependencies and tools
# including rust / docker / docker-compose / nodejs etc.
$ bash scripts/install_all.sh

# set the keystore path and password env in `goerli.env` to test on goerli
$ source goerli.env

# compile zk circuits and setup circuits locally
# start databases and message queue with docker compose
# and launch all the services
# and a mock orders/trades generator
$ bash run.sh

# stop all the processes and destroy docker compose clusters
$ bash stop.sh
```

Some useful commands have been added to Makefile:

```
# print the L2 blocks status, total block number, prover block number, etc.
$ make prover_status

# print the latest trades generated by matchengine
$ make new_trades

```

Now you can also attach a prove client cluster to the backend, see [the document](docs/client-cluster.md)

# Persist Data

NOTE: for the first time, DO NOT set `DX_CLEAN` before `run.sh`.
set env `DX_CLEAN` with `false` (case insensitive) to skip data purging stage when execute `stop.sh`.

# TODOs

* Data availability. And change original inputs as private, then use their hash as the (single) public input.
* Local dev-net might be broken cause by recent changes (move to goerli).

# Known Issues

* In order signature verification, user nonce and order id should be, but haven't yet been, signed.
* For test convenience, common reference string (CRS) is setup locally rather than by MPC.
