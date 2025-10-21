;; title: BitoCoin
;; version: 1.0.0
;; summary: Bitcoin-Backed Stablecoin Protocol

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u1000))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u1001))
(define-constant ERR_INVALID_AMOUNT (err u1002))
(define-constant ERR_POSITION_NOT_FOUND (err u1003))
(define-constant ERR_LIQUIDATION_THRESHOLD_NOT_MET (err u1004))
(define-constant ERR_INSUFFICIENT_BALANCE (err u1005))
(define-constant ERR_ORACLE_UPDATE_TOO_RECENT (err u1006))
(define-constant ERR_PRICE_TOO_OLD (err u1007))
(define-constant ERR_INSUFFICIENT_STAKE (err u1008))
(define-constant ERR_EMERGENCY_ACTIVE (err u1009))
(define-constant ERR_EMERGENCY_INACTIVE (err u1010))
(define-constant ERR_DEBT_TOO_LARGE (err u1011))
(define-constant ERR_REBALANCE_UNSAFE (err u1012))

(define-constant COLLATERAL_RATIO u150)
(define-constant LIQUIDATION_RATIO u120)
(define-constant LIQUIDATION_PENALTY u110)
(define-constant ORACLE_UPDATE_INTERVAL u144)
(define-constant PRICE_STALENESS_THRESHOLD u1440)

(define-data-var btc-price uint u50000000000)
(define-data-var last-price-update uint u0)
(define-data-var total-supply uint u0)
(define-data-var total-collateral uint u0)
(define-data-var total-staked uint u0)
(define-data-var reward-rate-per-block uint u100)
(define-data-var vault-admin principal CONTRACT_OWNER)
(define-data-var emergency-flag bool false)

(define-map positions 
    principal 
    {
        collateral: uint,
        debt: uint,
        created-at: uint
    }
)

(define-map balances principal uint)

(define-map allowances 
    {owner: principal, spender: principal} 
    uint
)

(define-map stakers
    principal
    {
        amount: uint,
        reward-debt: uint,
        last-block: uint
    }
)

(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

(define-read-only (get-balance (account principal))
    (default-to u0 (map-get? balances account))
)

(define-read-only (get-total-supply)
    (var-get total-supply)
)

(define-read-only (get-position (user principal))
    (map-get? positions user)
)

(define-read-only (get-btc-price)
    (var-get btc-price)
)

(define-read-only (get-collateral-ratio (user principal))
    (match (get-position user)
        position 
        (let ((collateral-value (* (get collateral position) (var-get btc-price)))
              (debt-value (* (get debt position) u1000000)))
            (if (> (get debt position) u0)
                (some (/ (* collateral-value u100) debt-value))
                none))
        none
    )
)

(define-read-only (calculate-max-mintable (collateral-amount uint))
    (let ((collateral-value (* collateral-amount (var-get btc-price))))
        (/ (* collateral-value u100) (* COLLATERAL_RATIO u1000000))
    )
)

(define-read-only (is-position-liquidatable (user principal))
    (match (get-collateral-ratio user)
        ratio (< ratio LIQUIDATION_RATIO)
        false
    )
)

(define-read-only (get-allowance (owner principal) (spender principal))
    (default-to u0 (map-get? allowances {owner: owner, spender: spender}))
)

(define-read-only (get-staked (user principal))
    (match (map-get? stakers user)
        staker-data (get amount staker-data)
        u0
    )
)

(define-read-only (get-pending-rewards (user principal))
    (let ((staker-data (default-to {amount: u0, reward-debt: u0, last-block: u0} (map-get? stakers user)))
          (total-staked-amount (var-get total-staked))
          (blocks-elapsed (- stacks-block-height (get last-block staker-data))))
        (if (and (> (get amount staker-data) u0) (> total-staked-amount u0) (> blocks-elapsed u0))
            (let ((user-share (* (get amount staker-data) u1000000))
                  (pool-share (/ user-share total-staked-amount))
                  (block-rewards (* blocks-elapsed (var-get reward-rate-per-block)))
                  (user-rewards (/ (* block-rewards pool-share) u1000000)))
                (+ (get reward-debt staker-data) user-rewards))
            (get reward-debt staker-data))))

(define-read-only (get-total-staked)
    (var-get total-staked)
)

(define-read-only (get-reward-rate)
    (var-get reward-rate-per-block)
)

(define-read-only (get-emergency-status)
    (var-get emergency-flag)
)

(define-private (transfer-token (from principal) (to principal) (amount uint))
    (let ((from-balance (get-balance from))
          (to-balance (get-balance to)))
        (asserts! (<= amount from-balance) ERR_INSUFFICIENT_BALANCE)
        (map-set balances from (- from-balance amount))
        (map-set balances to (+ to-balance amount))
        (ok true)
    )
)

(define-private (update-user-rewards (user principal))
    (let ((staker-data (default-to {amount: u0, reward-debt: u0, last-block: stacks-block-height} (map-get? stakers user)))
          (pending (get-pending-rewards user)))
        (map-set stakers user (merge staker-data {reward-debt: pending, last-block: stacks-block-height}))
        (ok pending)
    )
)

(define-private (is-vault-admin)
    (is-eq tx-sender (var-get vault-admin))
)

(define-public (update-btc-price (new-price uint))
    (let ((current-block stacks-block-height))
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (> new-price u0) ERR_INVALID_AMOUNT)
        (asserts! 
            (>= current-block 
                (+ (var-get last-price-update) ORACLE_UPDATE_INTERVAL)) 
            ERR_ORACLE_UPDATE_TOO_RECENT
        )
        (var-set btc-price new-price)
        (var-set last-price-update current-block)
        (ok new-price)
    )
)

(define-private (is-price-fresh)
    (<= (- stacks-block-height (var-get last-price-update)) PRICE_STALENESS_THRESHOLD)
)

(define-public (deposit-collateral (amount uint))
    (let ((current-position (default-to 
                                {collateral: u0, debt: u0, created-at: stacks-block-height} 
                                (get-position tx-sender))))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-price-fresh) ERR_PRICE_TOO_OLD)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set positions tx-sender 
            (merge current-position {collateral: (+ (get collateral current-position) amount)}))
        (var-set total-collateral (+ (var-get total-collateral) amount))
        (ok amount)
    )
)

(define-public (mint-tokens (amount uint))
    (let ((position (unwrap! (get-position tx-sender) ERR_POSITION_NOT_FOUND))
          (max-mintable (calculate-max-mintable (get collateral position)))
          (new-debt (+ (get debt position) amount)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-price-fresh) ERR_PRICE_TOO_OLD)
        (asserts! (<= new-debt max-mintable) ERR_INSUFFICIENT_COLLATERAL)
        (map-set positions tx-sender (merge position {debt: new-debt}))
        (map-set balances tx-sender (+ (get-balance tx-sender) amount))
        (var-set total-supply (+ (var-get total-supply) amount))
        (ok amount)
    )
)

(define-public (burn-tokens (amount uint))
    (let ((position (unwrap! (get-position tx-sender) ERR_POSITION_NOT_FOUND))
          (current-balance (get-balance tx-sender)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount current-balance) ERR_INSUFFICIENT_BALANCE)
        (asserts! (<= amount (get debt position)) ERR_INVALID_AMOUNT)
        (map-set positions tx-sender 
            (merge position {debt: (- (get debt position) amount)}))
        (map-set balances tx-sender (- current-balance amount))
        (var-set total-supply (- (var-get total-supply) amount))
        (ok amount)
    )
)

(define-public (rebalance-debt (amount uint))
    (let ((position (unwrap! (get-position tx-sender) ERR_POSITION_NOT_FOUND))
          (current-debt (get debt position))
          (collateral-amount (get collateral position))
          (new-debt (- current-debt amount))
          (collateral-value (* collateral-amount (var-get btc-price)))
          (required-collateral (* (* new-debt u1000000) COLLATERAL_RATIO))
          (balance-after-burn (- (get-balance tx-sender) amount)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount current-debt) ERR_DEBT_TOO_LARGE)
        (asserts! (is-price-fresh) ERR_PRICE_TOO_OLD)
        (asserts! (>= collateral-value required-collateral) ERR_REBALANCE_UNSAFE)
        (asserts! (>= (get-balance tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
        (try! (transfer-token tx-sender (as-contract tx-sender) amount))
        (map-set positions tx-sender (merge position {debt: new-debt}))
        (var-set total-supply (- (var-get total-supply) amount))
        (ok {debt-reduced: amount, new-debt: new-debt, collateral: collateral-amount})
    )
)

(define-public (withdraw-collateral (amount uint))
    (let ((position (unwrap! (get-position tx-sender) ERR_POSITION_NOT_FOUND))
          (remaining-collateral (- (get collateral position) amount)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount (get collateral position)) ERR_INSUFFICIENT_BALANCE)
        (asserts! (is-price-fresh) ERR_PRICE_TOO_OLD)
        (if (> (get debt position) u0)
            (let ((max-mintable-after (calculate-max-mintable remaining-collateral)))
                (asserts! (<= (get debt position) max-mintable-after) ERR_INSUFFICIENT_COLLATERAL)
                true)
            true)
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (map-set positions tx-sender 
            (merge position {collateral: remaining-collateral}))
        (var-set total-collateral (- (var-get total-collateral) amount))
        (ok amount)
    )
)

(define-public (liquidate (user principal))
    (let ((position (unwrap! (get-position user) ERR_POSITION_NOT_FOUND))
          (debt-amount (get debt position))
          (collateral-amount (get collateral position))
          (liquidator-balance (get-balance tx-sender))
          (penalty-amount (/ (* collateral-amount LIQUIDATION_PENALTY) u100)))
        (asserts! (is-position-liquidatable user) ERR_LIQUIDATION_THRESHOLD_NOT_MET)
        (asserts! (>= liquidator-balance debt-amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (is-price-fresh) ERR_PRICE_TOO_OLD)
        (try! (transfer-token tx-sender (as-contract tx-sender) debt-amount))
        (try! (as-contract (stx-transfer? penalty-amount tx-sender tx-sender)))
        (map-delete positions user)
        (var-set total-supply (- (var-get total-supply) debt-amount))
        (var-set total-collateral (- (var-get total-collateral) collateral-amount))
        (ok penalty-amount)
    )
)

(define-public (transfer (recipient principal) (amount uint))
    (begin
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (try! (transfer-token tx-sender recipient amount))
        (ok true)
    )
)

(define-public (approve (spender principal) (amount uint))
    (begin
        (map-set allowances {owner: tx-sender, spender: spender} amount)
        (ok true)
    )
)

(define-public (transfer-from (sender principal) (recipient principal) (amount uint))
    (let ((allowance (get-allowance sender tx-sender)))
        (asserts! (>= allowance amount) ERR_UNAUTHORIZED)
        (try! (transfer-token sender recipient amount))
        (map-set allowances {owner: sender, spender: tx-sender} (- allowance amount))
        (ok true)
    )
)

(define-public (stake (amount uint))
    (let ((current-staker (default-to {amount: u0, reward-debt: u0, last-block: stacks-block-height} (map-get? stakers tx-sender)))
          (user-balance (get-balance tx-sender)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get emergency-flag)) ERR_EMERGENCY_ACTIVE)
        (asserts! (<= amount user-balance) ERR_INSUFFICIENT_BALANCE)
        (unwrap! (update-user-rewards tx-sender) ERR_UNAUTHORIZED)
        (try! (transfer-token tx-sender (as-contract tx-sender) amount))
        (map-set stakers tx-sender 
            (merge current-staker 
                {amount: (+ (get amount current-staker) amount), 
                 last-block: stacks-block-height}))
        (var-set total-staked (+ (var-get total-staked) amount))
        (print {event: "stake", user: tx-sender, amount: amount})
        (ok amount)
    )
)

(define-public (unstake (amount uint))
    (let ((staker-data (unwrap! (map-get? stakers tx-sender) ERR_POSITION_NOT_FOUND))
          (pending-rewards (unwrap! (update-user-rewards tx-sender) ERR_UNAUTHORIZED)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get emergency-flag)) ERR_EMERGENCY_ACTIVE)
        (asserts! (<= amount (get amount staker-data)) ERR_INSUFFICIENT_STAKE)
        (try! (as-contract (transfer-token tx-sender tx-sender amount)))
        (if (> pending-rewards u0)
            (begin
                (map-set balances tx-sender (+ (get-balance tx-sender) pending-rewards))
                (var-set total-supply (+ (var-get total-supply) pending-rewards))
                true)
            true)
        (let ((remaining-amount (- (get amount staker-data) amount)))
            (if (is-eq remaining-amount u0)
                (map-delete stakers tx-sender)
                (map-set stakers tx-sender 
                    (merge staker-data 
                        {amount: remaining-amount, 
                         reward-debt: u0, 
                         last-block: stacks-block-height}))))
        (var-set total-staked (- (var-get total-staked) amount))
        (print {event: "unstake", user: tx-sender, amount: amount, rewards: pending-rewards})
        (ok {unstaked: amount, rewards: pending-rewards})
    )
)

(define-public (claim-rewards)
    (let ((pending-rewards (unwrap! (update-user-rewards tx-sender) ERR_UNAUTHORIZED)))
        (asserts! (> pending-rewards u0) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get emergency-flag)) ERR_EMERGENCY_ACTIVE)
        (map-set balances tx-sender (+ (get-balance tx-sender) pending-rewards))
        (var-set total-supply (+ (var-get total-supply) pending-rewards))
        (let ((current-staker (unwrap! (map-get? stakers tx-sender) ERR_POSITION_NOT_FOUND)))
            (map-set stakers tx-sender 
                (merge current-staker 
                    {reward-debt: u0, last-block: stacks-block-height})))
        (print {event: "claim", user: tx-sender, rewards: pending-rewards})
        (ok pending-rewards)
    )
)

(define-public (emergency-unstake)
    (let ((staker-data (unwrap! (map-get? stakers tx-sender) ERR_POSITION_NOT_FOUND)))
        (asserts! (var-get emergency-flag) ERR_EMERGENCY_INACTIVE)
        (try! (as-contract (transfer-token tx-sender tx-sender (get amount staker-data))))
        (var-set total-staked (- (var-get total-staked) (get amount staker-data)))
        (map-delete stakers tx-sender)
        (print {event: "emergency-unstake", user: tx-sender, amount: (get amount staker-data)})
        (ok (get amount staker-data))
    )
)

(define-public (set-reward-rate (new-rate uint))
    (begin
        (asserts! (is-vault-admin) ERR_UNAUTHORIZED)
        (asserts! (> new-rate u0) ERR_INVALID_AMOUNT)
        (var-set reward-rate-per-block new-rate)
        (print {event: "reward-rate-changed", new-rate: new-rate})
        (ok new-rate)
    )
)

(define-public (toggle-emergency)
    (begin
        (asserts! (is-vault-admin) ERR_UNAUTHORIZED)
        (let ((current-status (var-get emergency-flag)))
            (var-set emergency-flag (not current-status))
            (print {event: "emergency-toggled", status: (not current-status)})
            (ok (not current-status)))
    )
)

(define-public (set-vault-admin (new-admin principal))
    (begin
        (asserts! (is-vault-admin) ERR_UNAUTHORIZED)
        (var-set vault-admin new-admin)
        (print {event: "vault-admin-changed", new-admin: new-admin})
        (ok new-admin)
    )
)

(define-public (emergency-shutdown)
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (ok true)
    )
)

(begin
    (var-set last-price-update stacks-block-height)
)
