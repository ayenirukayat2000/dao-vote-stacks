import { describe, expect, it } from "vitest";
import { initSimnet } from "@hirosystems/clarinet-sdk";

const simnet = await initSimnet();

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;

describe("DAO Vote Stacks Tests", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("can create a proposal", () => {
    const { result } = simnet.callPublicFn(
      "dao-vote-stacks",
      "create-proposal",
      [
        "Test Proposal",
        1000, // duration in blocks
        1000000 // deposit (1 STX)
      ],
      address1
    );
    expect(result).toBeOk();
  });

  it("can vote on a proposal", () => {
    // First create a proposal
    simnet.callPublicFn(
      "dao-vote-stacks",
      "create-proposal",
      [
        "Test Proposal",
        1000,
        1000000
      ],
      address1
    );

    // Then vote on it
    const { result } = simnet.callPublicFn(
      "dao-vote-stacks",
      "vote",
      [
        0, // proposal-id
        true, // support
        100000 // vote amount
      ],
      address2
    );
    expect(result).toBeOk();
  });

  it("can get proposal details", () => {
    // Create a proposal first
    simnet.callPublicFn(
      "dao-vote-stacks",
      "create-proposal",
      [
        "Test Proposal",
        1000,
        1000000
      ],
      address1
    );

    // Get proposal details
    const { result } = simnet.callReadOnlyFn(
      "dao-vote-stacks",
      "get-proposal",
      [0],
      address1
    );
    expect(result).toBeOk();
  });
});