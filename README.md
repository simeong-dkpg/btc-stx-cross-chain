# Bitcoin-Stacks Cross-Chain Bridge

A secure, validator-consensus bridge protocol enabling seamless Bitcoin transfers to the Stacks blockchain with cryptographic verification and multi-signature security.

## Overview

The Bitcoin-Stacks Bridge facilitates trustless cross-chain asset transfers between Bitcoin and Stacks networks. The protocol employs a multi-validator consensus mechanism with cryptographic signature verification to ensure transaction integrity and prevent double-spending attacks.

### Key Features

- **Multi-Validator Consensus** - Distributed validation for enhanced security
- **Cryptographic Verification** - ECDSA signature validation for all transactions
- **Emergency Controls** - Pause/resume functionality for operational safety
- **Balance Management** - Comprehensive tracking with overflow protection
- **Configurable Limits** - Adjustable deposit/withdrawal thresholds
- **Event Logging** - Complete audit trail for monitoring and compliance

## System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Bitcoin       │    │   Validators    │    │   Stacks        │
│   Network       │    │   (Off-chain)   │    │   Blockchain    │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │ BTC Deposit│  │    │  │ Monitor   │  │    │  │ Bridge    │  │
│  │ Address   │  │────┼──┤ BTC Chain │  │────┼──┤ Contract  │  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │ Withdrawal│  │    │  │ Validate  │  │    │  │ User      │  │
│  │ Processing│  │◄───┼──┤ & Sign    │  │◄───┼──┤ Balances  │  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Contract Architecture

### Core Components

#### 1. **Validator Management**

- Authorized validator registry
- Multi-signature consensus requirement
- Dynamic validator addition/removal

#### 2. **Deposit Processing**

- Bitcoin transaction monitoring
- Confirmation requirement (6 blocks)
- Cryptographic proof verification

#### 3. **Balance Management**

- User balance tracking
- Withdrawal processing
- Emergency recovery mechanisms

#### 4. **Security Controls**

- Pause/resume functionality
- Amount validation (min/max limits)
- Anti-replay protection

### Data Structures

```clarity
;; Deposit Record
{
  amount: uint,           // Deposit amount in satoshis
  recipient: principal,   // Stacks recipient address
  processed: bool,        // Processing status
  confirmations: uint,    // Bitcoin confirmations
  timestamp: uint,        // Block height
  btc-sender: (buff 33)   // Bitcoin sender address
}

;; Validator Signature
{
  signature: (buff 65),   // ECDSA signature
  timestamp: uint         // Validation timestamp
}
```

## Data Flow

### Deposit Flow (Bitcoin → Stacks)

```
1. User sends BTC to bridge address
2. Validators detect transaction
3. Validator calls initiate-deposit()
4. Transaction waits for confirmations
5. Multiple validators sign confirmation
6. confirm-deposit() processes transaction
7. User receives bridged balance
```

### Withdrawal Flow (Stacks → Bitcoin)

```
1. User calls withdraw() function
2. Contract validates balance/amount
3. Balance deducted from user account
4. Withdrawal event emitted
5. Validators process Bitcoin payout
6. Bitcoin sent to specified address
```

## Configuration Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `MIN-DEPOSIT-AMOUNT` | 100,000 sat | Minimum deposit (0.001 BTC) |
| `MAX-DEPOSIT-AMOUNT` | 1B sat | Maximum deposit (10 BTC) |
| `REQUIRED-CONFIRMATIONS` | 6 blocks | Bitcoin confirmation requirement |

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 1000 | `ERROR-NOT-AUTHORIZED` | Unauthorized access attempt |
| 1001 | `ERROR-INVALID-AMOUNT` | Amount outside valid range |
| 1002 | `ERROR-INSUFFICIENT-BALANCE` | Insufficient balance for operation |
| 1003 | `ERROR-INVALID-BRIDGE-STATUS` | Invalid bridge operational state |
| 1004 | `ERROR-INVALID-SIGNATURE` | Cryptographic signature validation failed |
| 1005 | `ERROR-ALREADY-PROCESSED` | Transaction already processed |
| 1006 | `ERROR-BRIDGE-PAUSED` | Bridge operations currently paused |

## Security Considerations

### Multi-Validator Consensus

- Prevents single point of failure
- Requires majority validator agreement
- Cryptographic signature verification

### Transaction Validation

- Bitcoin confirmation requirements
- Anti-replay protection mechanisms
- Amount limit enforcement

### Emergency Controls

- Administrative pause functionality
- Emergency withdrawal capabilities
- Validator management controls

## Usage Examples

### Administrative Setup

```clarity
;; Initialize bridge
(contract-call? .bridge initialize-bridge)

;; Add validators
(contract-call? .bridge add-validator 'SP1VALIDATOR1...)
(contract-call? .bridge add-validator 'SP2VALIDATOR2...)
```

### User Operations

```clarity
;; Check balance
(contract-call? .bridge get-bridge-balance tx-sender)

;; Withdraw to Bitcoin
(contract-call? .bridge withdraw u500000 0x1a2b3c4d...)
```

### Validator Operations

```clarity
;; Initiate deposit
(contract-call? .bridge initiate-deposit 
  0xdeadbeef... u1000000 'SP3USER... 0x1234...)

;; Confirm deposit
(contract-call? .bridge confirm-deposit 
  0xdeadbeef... 0xsignature...)
```

## Monitoring & Events

The bridge emits events for external monitoring:

```clarity
{
  type: "withdraw",
  sender: principal,
  amount: uint,
  btc-recipient: (buff 34),
  timestamp: uint
}
```

## Deployment Requirements

- Stacks blockchain network access
- Authorized validator nodes
- Bitcoin network monitoring infrastructure
- Multi-signature wallet setup for Bitcoin operations

## License

MIT License - See LICENSE file for details

## Contributing

Please review our contributing guidelines and security policies before submitting pull requests.
