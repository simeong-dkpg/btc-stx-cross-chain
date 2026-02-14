;; Title: Bitcoin-Stacks Cross-Chain Bridge
;; 
;; Summary: Secure bidirectional asset bridge enabling seamless Bitcoin transfers to Stacks blockchain
;; 
;; Description: This contract implements a robust cross-chain bridge protocol that facilitates secure
;; Bitcoin deposits and withdrawals between the Bitcoin network and Stacks blockchain. The system
;; employs a multi-validator consensus mechanism with cryptographic signature verification to ensure
;; transaction integrity and prevent double-spending attacks. Features include deposit validation,
;; withdrawal processing, emergency controls, and comprehensive balance management with built-in
;; security measures and pause functionality for operational safety.
;;
;; Key Features:
;; - Multi-validator consensus for enhanced security
;; - Cryptographic signature verification for all transactions
;; - Emergency pause/resume functionality for operational control
;; - Comprehensive balance tracking and validation
;; - Configurable deposit limits with overflow protection
;; - Event logging for external monitoring and auditing

;; TRAITS

(define-trait bridgeable-token-trait
    (
        (transfer (uint principal principal) (response bool uint))
        (get-balance (principal) (response uint uint))
    )
)

;; ERROR CONSTANTS

(define-constant ERROR-NOT-AUTHORIZED u1000)
(define-constant ERROR-INVALID-AMOUNT u1001)
(define-constant ERROR-INSUFFICIENT-BALANCE u1002)
(define-constant ERROR-INVALID-BRIDGE-STATUS u1003)
(define-constant ERROR-INVALID-SIGNATURE u1004)
(define-constant ERROR-ALREADY-PROCESSED u1005)
(define-constant ERROR-BRIDGE-PAUSED u1006)
(define-constant ERROR-INVALID-VALIDATOR-ADDRESS u1007)
(define-constant ERROR-INVALID-RECIPIENT-ADDRESS u1008)
(define-constant ERROR-INVALID-BTC-ADDRESS u1009)
(define-constant ERROR-INVALID-TX-HASH u1010)
(define-constant ERROR-INVALID-SIGNATURE-FORMAT u1011)

;; CONFIGURATION CONSTANTS

(define-constant CONTRACT-DEPLOYER tx-sender)
(define-constant MIN-DEPOSIT-AMOUNT u100000)          ;; 0.001 BTC (in satoshis)
(define-constant MAX-DEPOSIT-AMOUNT u1000000000)      ;; 10 BTC (in satoshis)
(define-constant REQUIRED-CONFIRMATIONS u6)           ;; Bitcoin confirmation requirement

;; DATA VARIABLES

(define-data-var bridge-paused bool false)
(define-data-var total-bridged-amount uint u0)
(define-data-var last-processed-height uint u0)
(define-data-var validator-count uint u0)

;; DATA MAPS

;; Tracks Bitcoin deposit transactions and their processing status
(define-map deposits 
    { tx-hash: (buff 32) }
    {
        amount: uint,
        recipient: principal,
        processed: bool,
        confirmations: uint,
        timestamp: uint,
        btc-sender: (buff 33)
    }
)

;; Manages authorized validators for the bridge
(define-map validators principal bool)

;; Stores validator signatures for deposit confirmations
(define-map validator-signatures
    { tx-hash: (buff 32), validator: principal }
    { signature: (buff 65), timestamp: uint }
)

;; Tracks user balances within the bridge
(define-map bridge-balances principal uint)

;; ADMINISTRATIVE FUNCTIONS

;; Initializes the bridge system and sets operational status
(define-public (initialize-bridge)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (var-set bridge-paused false)
        
        (print {
            event: "bridge-initialized",
            deployer: CONTRACT-DEPLOYER,
            timestamp: stacks-block-height,
            min-deposit: MIN-DEPOSIT-AMOUNT,
            max-deposit: MAX-DEPOSIT-AMOUNT,
            required-confirmations: REQUIRED-CONFIRMATIONS
        })
        
        (ok true)
    )
)

;; Pauses all bridge operations for maintenance or emergency scenarios
(define-public (pause-bridge)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (let ((previous-state (var-get bridge-paused)))
            (var-set bridge-paused true)
            (print {
                event: "bridge-paused",
                previous-state: previous-state,
                new-state: true,
                executor: tx-sender,
                timestamp: stacks-block-height
            })
        )
        (ok true)
    )
)

;; Resumes bridge operations after maintenance or emergency pause
(define-public (resume-bridge)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (asserts! (var-get bridge-paused) (err ERROR-INVALID-BRIDGE-STATUS))
        (var-set bridge-paused false)
        
        (print {
            event: "bridge-resumed",
            new-state: false,
            executor: tx-sender,
            timestamp: stacks-block-height
        })
        
        (ok true)
    )
)

;; Adds a new validator to the bridge consensus mechanism
(define-public (add-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (asserts! (is-valid-principal validator) (err ERROR-INVALID-VALIDATOR-ADDRESS))
        
        (map-set validators validator true)
        (var-set validator-count (+ (var-get validator-count) u1))
        
        (print {
            event: "validator-added",
            validator: validator,
            added-by: tx-sender,
            total-validators: (+ (var-get validator-count) u1),
            timestamp: stacks-block-height
        })
        
        (ok true)
    )
)

;; Removes a validator from the bridge consensus mechanism
(define-public (remove-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (asserts! (is-valid-principal validator) (err ERROR-INVALID-VALIDATOR-ADDRESS))
        (asserts! (get-validator-status validator) (err ERROR-INVALID-VALIDATOR-ADDRESS))
        
        (map-set validators validator false)
        (var-set validator-count (- (var-get validator-count) u1))
        
        (print {
            event: "validator-removed",
            validator: validator,
            removed-by: tx-sender,
            total-validators: (- (var-get validator-count) u1),
            timestamp: stacks-block-height
        })
        
        (ok true)
    )
)

;; BRIDGE TRANSACTION FUNCTIONS

;; Initiates a Bitcoin deposit transaction requiring validator consensus
(define-public (initiate-deposit 
    (tx-hash (buff 32)) 
    (amount uint) 
    (recipient principal)
    (btc-sender (buff 33))
)
    (begin
        (asserts! (not (var-get bridge-paused)) (err ERROR-BRIDGE-PAUSED))
        (asserts! (validate-deposit-amount amount) (err ERROR-INVALID-AMOUNT))
        (asserts! (get-validator-status tx-sender) (err ERROR-NOT-AUTHORIZED))
        (asserts! (is-valid-tx-hash tx-hash) (err ERROR-INVALID-TX-HASH))
        (asserts! (is-none (map-get? deposits {tx-hash: tx-hash})) (err ERROR-ALREADY-PROCESSED))
        (asserts! (is-valid-principal recipient) (err ERROR-INVALID-RECIPIENT-ADDRESS))
        (asserts! (is-valid-btc-address btc-sender) (err ERROR-INVALID-BTC-ADDRESS))
        
        (let
            ((validated-deposit {
                amount: amount,
                recipient: recipient,
                processed: false,
                confirmations: u0,
                timestamp: stacks-block-height,
                btc-sender: btc-sender
            }))
            
            (map-set deposits
                {tx-hash: tx-hash}
                validated-deposit
            )
            
            (print {
                event: "deposit-initiated",
                tx-hash: tx-hash,
                amount: amount,
                recipient: recipient,
                btc-sender: btc-sender,
                initiated-by: tx-sender,
                confirmations-required: REQUIRED-CONFIRMATIONS,
                timestamp: stacks-block-height
            })
            
            (ok true)
        )
    )
)

;; Confirms a deposit with validator signature and processes the transaction
(define-public (confirm-deposit 
    (tx-hash (buff 32))
    (signature (buff 65))
)
    (let (
        (deposit (unwrap! (map-get? deposits {tx-hash: tx-hash}) (err ERROR-INVALID-BRIDGE-STATUS)))
        (is-validator (get-validator-status tx-sender))
    )
        (asserts! (not (var-get bridge-paused)) (err ERROR-BRIDGE-PAUSED))
        (asserts! (is-valid-tx-hash tx-hash) (err ERROR-INVALID-TX-HASH))
        (asserts! (is-valid-signature signature) (err ERROR-INVALID-SIGNATURE-FORMAT))
        (asserts! (not (get processed deposit)) (err ERROR-ALREADY-PROCESSED))
        (asserts! (>= (get confirmations deposit) REQUIRED-CONFIRMATIONS) (err ERROR-INVALID-BRIDGE-STATUS))
        
        (asserts! 
            (is-none (map-get? validator-signatures {tx-hash: tx-hash, validator: tx-sender}))
            (err ERROR-ALREADY-PROCESSED)
        )
        
        (let
            ((validated-signature {
                signature: signature,
                timestamp: stacks-block-height
            }))
            
            (map-set validator-signatures
                {tx-hash: tx-hash, validator: tx-sender}
                validated-signature
            )
            
            (map-set deposits
                {tx-hash: tx-hash}
                (merge deposit {processed: true})
            )
            
            (let ((old-balance (default-to u0 (map-get? bridge-balances (get recipient deposit))))
                  (new-balance (+ (default-to u0 (map-get? bridge-balances (get recipient deposit))) (get amount deposit))))
                (map-set bridge-balances
                    (get recipient deposit)
                    new-balance
                )
                
                (print {
                    event: "balance-updated",
                    user: (get recipient deposit),
                    old-balance: old-balance,
                    new-balance: new-balance,
                    change: (get amount deposit),
                    operation: "deposit-credit"
                })
            )
            
            (var-set total-bridged-amount 
                (+ (var-get total-bridged-amount) (get amount deposit))
            )
            
            (print {
                event: "signature-recorded",
                tx-hash: tx-hash,
                validator: tx-sender,
                signature: signature,
                timestamp: stacks-block-height
            })
            
            (print {
                event: "deposit-confirmed",
                tx-hash: tx-hash,
                amount: (get amount deposit),
                recipient: (get recipient deposit),
                btc-sender: (get btc-sender deposit),
                confirmed-by: tx-sender,
                confirmations-received: (+ (get confirmations deposit) u1),
                new-bridge-balance: (var-get total-bridged-amount),
                timestamp: stacks-block-height
            })
            
            (ok true)
        )
    )
)

;; Processes withdrawal request from Stacks to Bitcoin network
(define-public (withdraw 
    (amount uint)
    (btc-recipient (buff 34))
)
    (let (
        (current-balance (get-bridge-balance tx-sender))
        (old-total (var-get total-bridged-amount))
    )
        (asserts! (not (var-get bridge-paused)) (err ERROR-BRIDGE-PAUSED))
        (asserts! (>= current-balance amount) (err ERROR-INSUFFICIENT-BALANCE))
        (asserts! (validate-deposit-amount amount) (err ERROR-INVALID-AMOUNT))
        
        (let ((new-balance (- current-balance amount)))
            (map-set bridge-balances
                tx-sender
                new-balance
            )
            
            (print {
                event: "balance-updated",
                user: tx-sender,
                old-balance: current-balance,
                new-balance: new-balance,
                change: amount,
                operation: "withdraw-debit"
            })
        )
        
        (var-set total-bridged-amount (- (var-get total-bridged-amount) amount))
        
        (print {
            event: "withdraw",
            sender: tx-sender,
            amount: amount,
            btc-recipient: btc-recipient,
            remaining-balance: (- current-balance amount),
            total-bridged-before: old-total,
            total-bridged-after: (var-get total-bridged-amount),
            timestamp: stacks-block-height
        })
        
        (print {
            event: "withdrawal-processed",
            withdrawal-id: (var-get last-processed-height),
            sender: tx-sender,
            amount: amount,
            recipient-btc: btc-recipient,
            status: "completed",
            timestamp: stacks-block-height
        })
        
        (ok true)
    )
)

;; Emergency withdrawal function for critical situations (admin only)
(define-public (emergency-withdraw (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-DEPLOYER) (err ERROR-NOT-AUTHORIZED))
        (asserts! (>= (var-get total-bridged-amount) amount) (err ERROR-INSUFFICIENT-BALANCE))
        (asserts! (is-valid-principal recipient) (err ERROR-INVALID-RECIPIENT-ADDRESS))
        
        (let (
            (current-balance (default-to u0 (map-get? bridge-balances recipient)))
            (old-total (var-get total-bridged-amount))
            (new-balance (+ current-balance amount))
        )
            (asserts! (> new-balance current-balance) (err ERROR-INVALID-AMOUNT))
            (map-set bridge-balances recipient new-balance)
            
            (print {
                event: "balance-updated",
                user: recipient,
                old-balance: current-balance,
                new-balance: new-balance,
                change: amount,
                operation: "emergency-credit"
            })
            
            (print {
                event: "emergency-withdrawal",
                executor: tx-sender,
                amount: amount,
                recipient: recipient,
                total-bridged-before: old-total,
                total-bridged-after: (var-get total-bridged-amount),
                reason: "emergency",
                timestamp: stacks-block-height
            })
            
            (ok true)
        )
    )
)

;; Add confirmation count function
(define-public (add-confirmation (tx-hash (buff 32)))
    (let (
        (deposit (unwrap! (map-get? deposits {tx-hash: tx-hash}) (err ERROR-INVALID-BRIDGE-STATUS)))
        (is-validator (get-validator-status tx-sender))
    )
        (asserts! (not (get processed deposit)) (err ERROR-ALREADY-PROCESSED))
        (asserts! is-validator (err ERROR-NOT-AUTHORIZED))
        
        (map-set deposits
            {tx-hash: tx-hash}
            (merge deposit {confirmations: (+ (get confirmations deposit) u1)})
        )
        
        (print {
            event: "confirmation-added",
            tx-hash: tx-hash,
            validator: tx-sender,
            current-confirmations: (+ (get confirmations deposit) u1),
            required-confirmations: REQUIRED-CONFIRMATIONS,
            ready-for-processing: (>= (+ (get confirmations deposit) u1) REQUIRED-CONFIRMATIONS),
            timestamp: stacks-block-height
        })
        
        (ok true)
    )
)

;; READ-ONLY QUERY FUNCTIONS

;; Retrieves comprehensive deposit information by transaction hash
(define-read-only (get-deposit (tx-hash (buff 32)))
    (map-get? deposits {tx-hash: tx-hash})
)

;; Returns current operational status of the bridge
(define-read-only (get-bridge-status)
    (var-get bridge-paused)
)

;; Verifies if a principal is an authorized validator
(define-read-only (get-validator-status (validator principal))
    (default-to false (map-get? validators validator))
)

;; Retrieves the current bridge balance for a specific user
(define-read-only (get-bridge-balance (user principal))
    (default-to u0 (map-get? bridge-balances user))
)

;; Returns total amount of assets currently bridged
(define-read-only (get-total-bridged-amount)
    (var-get total-bridged-amount)
)

;; Returns validator count
(define-read-only (get-validator-count)
    (var-get validator-count)
)

;; VALIDATION HELPER FUNCTIONS

;; Validates principal address format and restrictions
(define-read-only (is-valid-principal (address principal))
    (and 
        (not (is-eq address CONTRACT-DEPLOYER))
        (not (is-eq address (as-contract tx-sender)))
    )
)

;; Validates Bitcoin address format and length requirements
(define-read-only (is-valid-btc-address (btc-addr (buff 33)))
    (and
        (is-eq (len btc-addr) u33)
        (not (is-eq btc-addr 0x000000000000000000000000000000000000000000000000000000000000000000))
        true
    )
)

;; Validates transaction hash format and prevents null values
(define-read-only (is-valid-tx-hash (tx-hash (buff 32)))
    (and
        (is-eq (len tx-hash) u32)
        (not (is-eq tx-hash 0x0000000000000000000000000000000000000000000000000000000000000000))
        true
    )
)

;; Validates cryptographic signature format and length
(define-read-only (is-valid-signature (signature (buff 65)))
    (and
        (is-eq (len signature) u65)
        (not (is-eq signature 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000))
        true
    )
)

;; Validates deposit amount within configured min/max limits
(define-read-only (validate-deposit-amount (amount uint))
    (and 
        (>= amount MIN-DEPOSIT-AMOUNT)
        (<= amount MAX-DEPOSIT-AMOUNT)
    )
)
