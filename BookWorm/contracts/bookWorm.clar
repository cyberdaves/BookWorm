;; BookWorm - Reading League Smart Contract

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-READER-DUPLICATE (err u101))
(define-constant ERR-READER-ABSENT (err u102))
(define-constant ERR-OBJECTIVE-ERROR (err u103))
(define-constant ERR-VAULT-SHORTAGE (err u104))
(define-constant ERR-AMOUNT-ERROR (err u105))
(define-constant ERR-SESSION-ERROR (err u106))
(define-constant ERR-QUEST-ERROR (err u107))

;; Data variables
(define-data-var library-keeper principal tx-sender)
(define-data-var knowledge-vault uint u0)
(define-data-var reader-population uint u0)

;; Data maps
(define-map book-readers
    principal
    {
        wisdom-points: uint,
        reading-sessions: uint,
        scholar-tier: uint,
        last-session-time: uint,
        wisdom-tokens: uint,
        current-quests: uint
    }
)

(define-map reading-quests
    {reader: principal, quest-number: uint}
    {
        pages-target: uint,
        pages-completed: uint,
        quest-timeout: uint,
        quest-finished: bool,
        knowledge-reward: uint,
        book-genre: (string-ascii 20)
    }
)

(define-map scholar-honors
    principal
    (list 10 (string-ascii 30))
)

;; Public functions

;; Reader enrollment
(define-public (join-reading-league)
    (let
        ((enrollee tx-sender))
        (asserts! (is-none (map-get? book-readers enrollee)) (err ERR-READER-DUPLICATE))
        (map-set book-readers
            enrollee
            {
                wisdom-points: u0,
                reading-sessions: u0,
                scholar-tier: u1,
                last-session-time: burn-block-height,
                wisdom-tokens: u0,
                current-quests: u0
            }
        )
        (var-set reader-population (+ (var-get reader-population) u1))
        (ok true)
    )
)

;; Start reading quest
(define-public (begin-reading-quest (page-objective uint) (time-limit uint) (genre-type (string-ascii 20)))
    (let
        ((reader tx-sender)
         (reader-profile (unwrap! (map-get? book-readers reader) ERR-READER-ABSENT))
         (quest-number (+ (get current-quests reader-profile) u1)))
        
        (asserts! (> page-objective u0) ERR-OBJECTIVE-ERROR)
        (asserts! (> time-limit burn-block-height) ERR-OBJECTIVE-ERROR)
        (asserts! (<= (len genre-type) u20) ERR-OBJECTIVE-ERROR)
        
        (map-set reading-quests
            {reader: reader, quest-number: quest-number}
            {
                pages-target: page-objective,
                pages-completed: u0,
                quest-timeout: time-limit,
                quest-finished: false,
                knowledge-reward: (derive-knowledge-reward page-objective),
                book-genre: genre-type
            }
        )
        
        (map-set book-readers
            reader
            (merge reader-profile {current-quests: quest-number})
        )
        (ok quest-number)
    )
)

;; Log reading progress
(define-public (submit-reading-progress (quest-number uint) (pages-read uint))
    (let
        ((reader tx-sender)
         (reader-profile (unwrap! (map-get? book-readers reader) ERR-READER-ABSENT)))
        
        (asserts! (> pages-read u0) ERR-SESSION-ERROR)
        (asserts! (<= quest-number (get current-quests reader-profile)) ERR-QUEST-ERROR)
        
        (let
            ((quest-details (unwrap! (map-get? reading-quests {reader: reader, quest-number: quest-number}) ERR-QUEST-ERROR))
             (time-now burn-block-height))
            
            (asserts! (not (get quest-finished quest-details)) ERR-OBJECTIVE-ERROR)
            (asserts! (<= time-now (get quest-timeout quest-details)) ERR-OBJECTIVE-ERROR)
            
            (let
                ((cumulative-pages (+ (get pages-completed quest-details) pages-read))
                 (objective-met (>= cumulative-pages (get pages-target quest-details)))
                 (wisdom-gain (derive-wisdom-points pages-read))
                 (total-wisdom (+ (get wisdom-points reader-profile) wisdom-gain)))
                
                ;; Update quest
                (map-set reading-quests
                    {reader: reader, quest-number: quest-number}
                    (merge quest-details {
                        pages-completed: cumulative-pages,
                        quest-finished: objective-met
                    })
                )
                
                ;; Update reader
                (map-set book-readers
                    reader
                    (merge reader-profile {
                        wisdom-points: total-wisdom,
                        reading-sessions: (+ (get reading-sessions reader-profile) u1),
                        last-session-time: time-now,
                        scholar-tier: (derive-scholar-tier total-wisdom)
                    })
                )
                
                ;; Grant honor if objective met
                (if objective-met
                    (confer-scholar-honor reader (concat "Finished " (get book-genre quest-details)))
                    true
                )
                
                (ok {
                    pages: cumulative-pages,
                    completed: objective-met,
                    wisdom: total-wisdom
                })
            )
        )
    )
)

;; Claim reading rewards
(define-public (collect-knowledge-reward (quest-number uint))
    (let
        ((reader tx-sender)
         (reader-profile (unwrap! (map-get? book-readers reader) ERR-READER-ABSENT)))
        
        (asserts! (<= quest-number (get current-quests reader-profile)) ERR-QUEST-ERROR)
        
        (let
            ((quest-details (unwrap! (map-get? reading-quests {reader: reader, quest-number: quest-number}) ERR-QUEST-ERROR)))
            
            (asserts! (get quest-finished quest-details) ERR-OBJECTIVE-ERROR)
            (asserts! (>= (var-get knowledge-vault) (get knowledge-reward quest-details)) ERR-VAULT-SHORTAGE)
            
            ;; Distribute reward
            (var-set knowledge-vault (- (var-get knowledge-vault) (get knowledge-reward quest-details)))
            (map-set book-readers
                reader
                (merge reader-profile {
                    wisdom-tokens: (+ (get wisdom-tokens reader-profile) (get knowledge-reward quest-details))
                })
            )
            
            (ok (get knowledge-reward quest-details))
        )
    )
)

;; Private functions

(define-private (derive-knowledge-reward (page-objective uint))
    (let
        ((base-multiplier u100))
        (* base-multiplier (/ page-objective u100))
    )
)

(define-private (derive-wisdom-points (pages-read uint))
    (* pages-read u10)
)

(define-private (derive-scholar-tier (total-wisdom uint))
    (+ u1 (/ total-wisdom u1000))
)

(define-private (confer-scholar-honor (reader principal) (honor-title (string-ascii 30)))
    (let
        ((existing-honors (default-to (list) (map-get? scholar-honors reader))))
        (map-set scholar-honors
            reader
            (unwrap-panic (as-max-len? (append existing-honors honor-title) u10))
        )
    )
)

;; Read-only functions

(define-read-only (fetch-reader-profile (reader principal))
    (map-get? book-readers reader)
)

(define-read-only (fetch-quest-details (reader principal) (quest-number uint))
    (map-get? reading-quests {reader: reader, quest-number: quest-number})
)

(define-read-only (fetch-reader-honors (reader principal))
    (map-get? scholar-honors reader)
)

(define-read-only (fetch-league-statistics)
    {
        total-readers: (var-get reader-population),
        vault-balance: (var-get knowledge-vault)
    }
)

;; Administrative functions

(define-public (replenish-knowledge-vault (token-sum uint))
    (begin
        (asserts! (is-eq tx-sender (var-get library-keeper)) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> token-sum u0) ERR-AMOUNT-ERROR)
        (var-set knowledge-vault (+ (var-get knowledge-vault) token-sum))
        (ok true)
    )
)

(define-public (designate-new-keeper (successor principal))
    (begin
        (asserts! (is-eq tx-sender (var-get library-keeper)) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (not (is-eq successor (var-get library-keeper))) ERR-UNAUTHORIZED-ACCESS)
        (var-set library-keeper successor)
        (ok true)
    )
)