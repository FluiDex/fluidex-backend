#!/bin/bash
set -uex

# assume already install: libgmp-dev nasm nlohmann-json3-dev snarkit plonkit

# TODO: detect file and skip

source ./envs/small
export VERBOSE=false
export RUST_BACKTRACE=full

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"
STATE_MNGR_DIR=$DIR/rollup-state-manager
CIRCUITS_DIR=$STATE_MNGR_DIR/circuits
TARGET_CIRCUIT_DIR=$CIRCUITS_DIR/testdata/Block_$NTXS"_"$BALANCELEVELS"_"$ORDERLEVELS"_"$ACCOUNTLEVELS
PROVER_DIR=$DIR/prover-cluster
EXCHANGE_DIR=$DIR/dingir-exchange
HEIMDALLR_DIR=$DIR/Heimdallr

function handle_submodule() {
  git submodule update --init --recursive
  if [ -z ${CI+x} ]; then git pull --recurse-submodules; fi
}

function prepare_circuit() {
  rm $TARGET_CIRCUIT_DIR -rf
  cd $STATE_MNGR_DIR
  cargo run --bin gen_export_circuit_testcase

  cd $CIRCUITS_DIR
  npm i
  # TODO: detect and install snarkit
  snarkit compile $TARGET_CIRCUIT_DIR --verbose --backend=native 2>&1 | tee /tmp/snarkit.log

  plonkit setup --power 20 --srs_monomial_form $TARGET_CIRCUIT_DIR/mon.key
  plonkit dump-lagrange -c $TARGET_CIRCUIT_DIR/circuit.r1cs --srs_monomial_form $TARGET_CIRCUIT_DIR/mon.key --srs_lagrange_form $TARGET_CIRCUIT_DIR/lag.key
  plonkit export-verification-key -c $TARGET_CIRCUIT_DIR/circuit.r1cs --srs_monomial_form $TARGET_CIRCUIT_DIR/mon.key -v $TARGET_CIRCUIT_DIR/vk.bin
}

function config_prover_cluster() {
  cd $PROVER_DIR

  PORT=50055 TARGET_CIRCUIT_DIR=$TARGET_CIRCUIT_DIR envsubst < $PROVER_DIR/config/coordinator.yaml.template > $PROVER_DIR/config/coordinator.yaml
  TARGET_CIRCUIT_DIR=$TARGET_CIRCUIT_DIR envsubst < $PROVER_DIR/config/client.yaml.template > $PROVER_DIR/config/client.yaml
}

# TODO: send different tasks to different tmux windows

function restart_docker_compose() {
  dir=$1
  name=$2
  docker-compose --file $dir/docker/docker-compose.yaml --project-name $name down
  sudo rm $dir/docker/data -rf
  docker-compose --file $dir/docker/docker-compose.yaml --project-name $name up --force-recreate --detach
}

function run_docker_compose() {
  restart_docker_compose $EXCHANGE_DIR docker
  restart_docker_compose $PROVER_DIR cluster
  restart_docker_compose $STATE_MNGR_DIR rollup
  restart_docker_compose $HEIMDALLR_DIR heimdallr
}

function run_matchengine() {
  cd $EXCHANGE_DIR
  make startall
  #cargo build --bin matchengine
  #nohup $EXCHANGE_DIR/target/debug/matchengine >> $EXCHANGE_DIR/matchengine.log 2>&1 &
}

function run_ticker() {
  cd $EXCHANGE_DIR/examples/js/
  npm i
  nohup npx ts-node tick.ts >> $EXCHANGE_DIR/tick.log 2>&1 &
}

function run_rollup() {
  cd $STATE_MNGR_DIR
  cargo build --release --bin rollup_state_manager
  DATABASE_URL=postgres://postgres:postgres_AA9944@127.0.0.1:5434/rollup_state_manager sqlx migrate run
  nohup $STATE_MNGR_DIR/target/release/rollup_state_manager >> $STATE_MNGR_DIR/rollup_state_manager.log 2>&1 &
}

function run_prove_master() {
  # run coordinator because we need to init db
  cd $PROVER_DIR
  cargo build --release
  nohup $PROVER_DIR/target/release/coordinator >> $PROVER_DIR/coordinator.log 2>&1 &
}

function run_prove_workers() {
  cd $PROVER_DIR # need to switch into PROVER_DIR to use .env
  if [ ! -f $PROVER_DIR/target/release/client ]; then
      cargo build --release
  fi
  nohup $PROVER_DIR/target/release/client >> $PROVER_DIR/client.log 2>&1 &
}

function run_faucet() {
  cd $HEIMDALLR_DIR
  cargo build --release --bin faucet
  nohup $HEIMDALLR_DIR/target/release/faucet >> $HEIMDALLR_DIR/faucet.log 2>&1 &
}

function run_bin() {
  run_matchengine
  run_ticker
  run_prove_master
  run_prove_workers
  run_rollup
  run_faucet
}

function main() {
  handle_submodule
  prepare_circuit
  config_prover_cluster
  run_docker_compose
  run_bin
}
main
