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

(define-constant COLLATERAL_RATIO u150)
(define-constant LIQUIDATION_RATIO u120)
(define-constant LIQUIDATION_PENALTY u110)
(define-constant ORACLE_UPDATE_INTERVAL u144)
(define-constant PRICE_STALENESS_THRESHOLD u1440)

(define-data-var btc-price uint u50000000000)
(define-data-var last-price-update uint u0)
(define-data-var total-supply uint u0)
(define-data-var total-collateral uint u0)

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

(define-private (transfer-token (from principal) (to principal) (amount uint))
    (let ((from-balance (get-balance from))
          (to-balance (get-balance to)))
        (asserts! (<= amount from-balance) ERR_INSUFFICIENT_BALANCE)
        (map-set balances from (- from-balance amount))
        (map-set balances to (+ to-balance amount))
        (ok true)
    )
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

(define-public (emergency-shutdown)
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (ok true)
    )
)

(begin
    (var-set last-price-update stacks-block-height)
)
