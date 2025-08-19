(define-constant ERR_PROPOSAL_EXISTS (err u100))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u101))
(define-constant ERR_VOTING_ENDED (err u102))
(define-constant ERR_VOTING_ONGOING (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_NOT_PROPOSER (err u105))
(define-constant ERR_ALREADY_EXECUTED (err u106))
(define-constant ERR_QUORUM_NOT_MET (err u107))
(define-constant ERR_NOT_ENOUGH_STX (err u108))
(define-constant MIN_PROPOSAL_DEPOSIT u1000000) ;; 1 STX minimum
(define-constant MIN_VOTE_AMOUNT u100000) ;; 0.1 STX minimum
(define-constant QUORUM u2000000) ;; 2 STX minimum quorum

;; Proposal structure
(define-map proposals
  { id: uint }
  {
    proposer: principal,
    description: (string-ascii 200),
    deposit: uint,
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    executed: bool
  }
)

;; Votes map
(define-map votes
  { proposal-id: uint, voter: principal }
  {
    amount: uint,
    support: bool
  }
)

;; Next proposal ID counter
(define-data-var next-proposal-id uint u0)

;; Create a proposal
(define-public (create-proposal (description (string-ascii 200)) (duration uint) (deposit uint))
  (let (
    (start stacks-block-height)
    (end (+ start duration))
    (id (var-get next-proposal-id))
  )
    (begin
      (asserts! (>= deposit MIN_PROPOSAL_DEPOSIT) ERR_NOT_ENOUGH_STX)
      (asserts! (> duration u0) ERR_NOT_ENOUGH_STX)
      (try! (stx-transfer? deposit tx-sender (as-contract tx-sender)))
      (map-set proposals
        { id: id }
        {
          proposer: tx-sender,
          description: (if (is-eq description "") "No description" description),
          deposit: deposit,
          start-block: start,
          end-block: (+ start duration),
          yes-votes: u0,
          no-votes: u0,
          executed: false
        }
      )
      (var-set next-proposal-id (+ id u1))
      (ok id)
    )
  )
)

;; Vote on a proposal
;; Vote on a proposal
(define-public (vote (proposal-id uint) (support bool) (vote-amount uint))
  (let (
    (current-block stacks-block-height)
  )
    (begin
      (asserts! (>= vote-amount MIN_VOTE_AMOUNT) ERR_NOT_ENOUGH_STX)
      (try! (stx-transfer? vote-amount tx-sender (as-contract tx-sender)))
      (let ((proposal-opt (map-get? proposals { id: proposal-id })))
        (asserts! (is-some proposal-opt) ERR_PROPOSAL_NOT_FOUND)
        (let ((proposal (unwrap-panic proposal-opt)))
          (begin
            (asserts! (<= (get start-block proposal) current-block) ERR_VOTING_ONGOING)
            (asserts! (< current-block (get end-block proposal)) ERR_VOTING_ENDED)
            (asserts! (not (is-some (map-get? votes { proposal-id: proposal-id, voter: tx-sender }))) ERR_ALREADY_VOTED)
            (let (
              (yes-votes (if support (+ (get yes-votes proposal) vote-amount) (get yes-votes proposal)))
              (no-votes (if support (get no-votes proposal) (+ (get no-votes proposal) vote-amount)))
            )
              (begin
                (map-set votes
                  { proposal-id: proposal-id, voter: tx-sender }
                  { amount: vote-amount, support: support }
                )
                (map-set proposals
                  { id: proposal-id }
                  (merge proposal {
                    yes-votes: yes-votes,
                    no-votes: no-votes
                  })
                )
                (ok true)
              )
            )
          )
        )
      )
    )
  )
)

;; Execute a proposal (if passed)
(define-public (execute-proposal (proposal-id uint))
  (let (
    (current-block stacks-block-height)
  )
    (begin
      (let ((proposal-opt (map-get? proposals { id: proposal-id })))
        (asserts! (is-some proposal-opt) ERR_PROPOSAL_NOT_FOUND)
        (let ((proposal (unwrap-panic proposal-opt)))
          (begin
            (asserts! (>= current-block (get end-block proposal)) ERR_VOTING_ONGOING)
            (asserts! (is-eq (get executed proposal) false) ERR_ALREADY_EXECUTED)
            (let (
              (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
              (yes-votes (get yes-votes proposal))
              (no-votes (get no-votes proposal))
            )
              (asserts! (>= total-votes QUORUM) ERR_QUORUM_NOT_MET)
              (asserts! (> yes-votes no-votes) ERR_QUORUM_NOT_MET)
              (ok (map-set proposals 
                { id: proposal-id }
                (merge proposal {
                  executed: true
                })))
            )
          )
        )
      )
    )
  )
)

;; Refund for proposer (only callable by proposer after voting ends)
(define-public (refund-proposer (proposal-id uint))
  (let (
    (current-block stacks-block-height)
  )
    (begin
      (let ((proposal-opt (map-get? proposals { id: proposal-id })))
        (asserts! (is-some proposal-opt) ERR_PROPOSAL_NOT_FOUND)
        (let (
          (proposal (unwrap-panic proposal-opt))
          (map-key { id: proposal-id })
        )
          (begin
            (asserts! (>= current-block (get end-block proposal)) ERR_VOTING_ONGOING)
            (asserts! (is-eq tx-sender (get proposer proposal)) ERR_NOT_PROPOSER)
            (let ((amount (get deposit proposal)))
              (asserts! (> amount u0) ERR_ALREADY_EXECUTED)
              (try! (stx-transfer? amount (as-contract tx-sender) tx-sender))
              (map-set proposals 
                map-key
                (merge proposal {
                  deposit: u0
                })
              )
              (ok true)
            )
          )
        )
      )
    )
  )
)

;; Refund for voter
(define-public (refund-voter (proposal-id uint))
  (let (
    (current-block stacks-block-height)
  )
    (begin
      (let ((proposal-opt (map-get? proposals { id: proposal-id })))
        (asserts! (is-some proposal-opt) ERR_PROPOSAL_NOT_FOUND)
        (let ((proposal (unwrap-panic proposal-opt)))
          (begin
            (asserts! (>= current-block (get end-block proposal)) ERR_VOTING_ONGOING)
            (let (
              (vote-key { proposal-id: proposal-id, voter: tx-sender })
              (vote-data-opt (map-get? votes vote-key))
            )
              (asserts! (is-some vote-data-opt) ERR_PROPOSAL_NOT_FOUND)
              (let (
                (vote-data (unwrap-panic vote-data-opt))
                (amount (get amount vote-data))
              )
                (begin
                  (try! (stx-transfer? amount (as-contract tx-sender) tx-sender))
                  (map-delete votes vote-key)
                  (ok true)
                )
              )
            )
          )
        )
      )
    )
  )
)

;; Read-only: Check proposal details
(define-read-only (get-proposal (proposal-id uint))
  (let ((proposal-opt (map-get? proposals { id: proposal-id })))
    (if (is-some proposal-opt)
      (ok (unwrap-panic proposal-opt))
      (err ERR_PROPOSAL_NOT_FOUND)
    )
  )
)

;; Read-only: Has a user voted?
(define-read-only (has-voted (proposal-id uint) (user principal))
  (ok (is-some (map-get? votes { proposal-id: proposal-id, voter: user })))
)

;; Read-only: Get vote details
(define-read-only (get-vote (proposal-id uint) (user principal))
  (let ((vote-opt (map-get? votes { proposal-id: proposal-id, voter: user })))
    (if (is-some vote-opt)
      (ok (unwrap-panic vote-opt))
      (err ERR_PROPOSAL_NOT_FOUND)
    )
  )
)