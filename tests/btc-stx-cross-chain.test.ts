import { describe, it, expect } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const user1 = accounts.get("wallet_1")!;
const user2 = accounts.get("wallet_2")!;
const validator1 = accounts.get("wallet_3")!;

// Helper function to generate dummy buffers
function dummyBuff(length: number): Uint8Array {
  return new Uint8Array(length).fill(1);
}

describe("Bitcoin-Stacks Bridge Contract - Full Test Suite", () => {

  it("ensures simnet is initialized", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  // ---------- ADMIN FUNCTIONS ----------
  it("initializes, pauses, and resumes bridge correctly", () => {
    // Only deployer can initialize
    expect(simnet.callTx("bridge", "initialize-bridge", [], deployer)).toBeOk();

    // Non-deployer cannot pause/resume
    expect(simnet.callTx("bridge", "pause-bridge", [], user1)).toBeErr();
    expect(simnet.callTx("bridge", "resume-bridge", [], user1)).toBeErr();

    // Deployer can pause/resume
    expect(simnet.callTx("bridge", "pause-bridge", [], deployer)).toBeOk();
    expect(simnet.callTx("bridge", "resume-bridge", [], deployer)).toBeOk();

    // Resuming when already resumed fails
    expect(simnet.callTx("bridge", "resume-bridge", [], deployer)).toBeErr();
  });

  it("adds/removes validators with correct checks", () => {
    // Invalid validator address
    expect(simnet.callTx("bridge", "add-validator", [deployer], deployer)).toBeErr();
    expect(simnet.callTx("bridge", "remove-validator", [deployer], deployer)).toBeErr();

    // Valid validator
    expect(simnet.callTx("bridge", "add-validator", [validator1], deployer)).toBeOk();
    expect(simnet.callTx("bridge", "remove-validator", [validator1], deployer)).toBeOk();
  });

  // ---------- DEPOSIT FUNCTIONS ----------
  it("prevents invalid deposits", () => {
    const txHash = dummyBuff(32);
    const btcAddr = dummyBuff(33);

    // Pause bridge prevents deposits
    simnet.callTx("bridge", "pause-bridge", [], deployer);
    expect(simnet.callTx("bridge", "initiate-deposit", [txHash, 100000, user1, btcAddr], validator1)).toBeErr();
    simnet.callTx("bridge", "resume-bridge", [], deployer);

    // Invalid amounts
    expect(simnet.callTx("bridge", "initiate-deposit", [txHash, 1, user1, btcAddr], validator1)).toBeErr();

    // Invalid tx hash
    expect(simnet.callTx("bridge", "initiate-deposit", [dummyBuff(31), 100000, user1, btcAddr], validator1)).toBeErr();

    // Invalid recipient
    expect(simnet.callTx("bridge", "initiate-deposit", [txHash, 100000, deployer, btcAddr], validator1)).toBeErr();

    // Invalid BTC address
    expect(simnet.callTx("bridge", "initiate-deposit", [txHash, 100000, user1, dummyBuff(32)], validator1)).toBeErr();

    // Non-validator cannot deposit
    expect(simnet.callTx("bridge", "initiate-deposit", [txHash, 100000, user1, btcAddr], user1)).toBeErr();
  });

  it("processes deposit correctly and prevents double processing", () => {
    const txHash = dummyBuff(32);
    const btcAddr = dummyBuff(33);
    const signature = dummyBuff(65);

    simnet.callTx("bridge", "add-validator", [validator1], deployer);

    // Initiate deposit
    expect(simnet.callTx("bridge", "initiate-deposit", [txHash, 100000, user1, btcAddr], validator1)).toBeOk();

    // Not enough confirmations
    expect(simnet.callTx("bridge", "confirm-deposit", [txHash, signature], validator1)).toBeErr();

    // Simulate confirmations
    simnet.updateMap("bridge", "deposits", { tx-hash: txHash }, { confirmations: 6 });

    // Confirm deposit successfully
    expect(simnet.callTx("bridge", "confirm-deposit", [txHash, signature], validator1)).toBeOk();

    // Double confirmation fails
    expect(simnet.callTx("bridge", "confirm-deposit", [txHash, signature], validator1)).toBeErr();
  });

  // ---------- WITHDRAWAL FUNCTIONS ----------
  it("prevents invalid withdrawals", () => {
    const btcRecipient = dummyBuff(34);

    // User with zero balance
    expect(simnet.callTx("bridge", "withdraw", [100, btcRecipient], user2)).toBeErr();

    // Invalid withdrawal amount
    expect(simnet.callTx("bridge", "withdraw", [1, btcRecipient], user1)).toBeErr();
  });

  it("executes emergency withdrawal with correct checks", () => {
    // Non-deployer fails
    expect(simnet.callTx("bridge", "emergency-withdraw", [100, user1], user1)).toBeErr();

    // Invalid recipient
    expect(simnet.callTx("bridge", "emergency-withdraw", [100, deployer], deployer)).toBeErr();

    // Too much amount
    expect(simnet.callTx("bridge", "emergency-withdraw", [1_000_000_000, user2], deployer)).toBeErr();

    // Successful emergency withdrawal
    expect(simnet.callTx("bridge", "emergency-withdraw", [1000, user1], deployer)).toBeOk();
  });

  // ---------- READ-ONLY FUNCTIONS ----------
  it("reads bridge data correctly", () => {
    const txHash = dummyBuff(32);

    expect(simnet.callReadOnlyFn("bridge", "get-bridge-status", [])).toBeDefined();
    expect(simnet.callReadOnlyFn("bridge", "get-validator-status", [validator1])).toBeDefined();
    expect(simnet.callReadOnlyFn("bridge", "get-bridge-balance", [user1])).toBeDefined();
    expect(simnet.callReadOnlyFn("bridge", "get-total-bridged-amount", [])).toBeDefined();
    expect(simnet.callReadOnlyFn("bridge", "get-deposit", [txHash])).toBeDefined();
  });

});
