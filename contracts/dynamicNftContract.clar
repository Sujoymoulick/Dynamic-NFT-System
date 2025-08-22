;; Define the NFT
(define-non-fungible-token dynamic-nft uint)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-token-not-found (err u102))
(define-constant err-invalid-token-id (err u103))
(define-constant err-metadata-frozen (err u104))

;; Data Variables
(define-data-var last-token-id uint u0)
(define-data-var base-uri (string-ascii 256) "https://api.dynamicnft.com/metadata/")

;; NFT Metadata Structure
(define-map token-metadata
    uint
    {
        name: (string-ascii 64),
        description: (string-ascii 256),
        image: (string-ascii 256),
        level: uint,
        experience: uint,
        last-update: uint,
        is-frozen: bool,
    }
)

;; Evolution Thresholds
(define-map evolution-thresholds
    uint ;; level
    uint ;; experience required
)

;; Level to string mapping for image URLs
(define-map level-strings
    uint
    (string-ascii 32)
)

;; Initialize evolution thresholds and level strings
(map-set evolution-thresholds u1 u100)
(map-set evolution-thresholds u2 u250)
(map-set evolution-thresholds u3 u500)
(map-set evolution-thresholds u4 u1000)
(map-set evolution-thresholds u5 u2000)

(map-set level-strings u1 "1")
(map-set level-strings u2 "2")
(map-set level-strings u3 "3")
(map-set level-strings u4 "4")
(map-set level-strings u5 "5")

;; Helper function to convert uint to string for levels 1-5
(define-private (uint-to-string (value uint))
    (default-to "1" (map-get? level-strings value))
)

;; Function 1: Mint Dynamic NFT
;; Mint a new dynamic NFT with initial metadata
(define-public (mint-dynamic-nft
        (recipient principal)
        (name (string-ascii 64))
        (description (string-ascii 256))
        (image (string-ascii 256))
    )
    (let ((token-id (+ (var-get last-token-id) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)

        ;; Mint the NFT
        (try! (nft-mint? dynamic-nft token-id recipient))

        ;; Set initial metadata
        (map-set token-metadata token-id {
            name: name,
            description: description,
            image: image,
            level: u1,
            experience: u0,
            last-update: stacks-block-height,
            is-frozen: false,
        })

        ;; Update last token ID
        (var-set last-token-id token-id)

        ;; Print mint event
        (print {
            action: "mint",
            token-id: token-id,
            recipient: recipient,
            name: name,
        })

        (ok token-id)
    )
)

;; Function 2: Update NFT Based on Conditions
;; Update NFT metadata based on external conditions (experience gain, time passage, etc.)
(define-public (update-nft-metadata
        (token-id uint)
        (experience-gain uint)
    )
    (let (
            (current-metadata (unwrap! (map-get? token-metadata token-id) err-token-not-found))
            (token-owner (unwrap! (nft-get-owner? dynamic-nft token-id) err-token-not-found))
            (new-experience (+ (get experience current-metadata) experience-gain))
            (current-level (get level current-metadata))
            (blocks-since-update (- stacks-block-height (get last-update current-metadata)))
        )
        ;; Check if caller is token owner or contract owner
        (asserts!
            (or (is-eq tx-sender token-owner) (is-eq tx-sender contract-owner))
            err-not-token-owner
        )

        ;; Check if metadata is not frozen
        (asserts! (not (get is-frozen current-metadata)) err-metadata-frozen)

        ;; Calculate new level based on experience
        (let (
                (new-level (calculate-level new-experience))
                (level-changed (not (is-eq new-level current-level)))
                (time-bonus (if (> blocks-since-update u144)
                    u10
                    u0
                )) ;; Bonus for inactive tokens (1 day = ~144 blocks)
                (final-experience (+ new-experience time-bonus))
                (level-string (uint-to-string new-level))
            )


            ;; Print update event
            (print {
                action: "update",
                token-id: token-id,
                old-level: current-level,
                new-level: new-level,
                experience-gained: experience-gain,
                time-bonus: time-bonus,
                level-up: level-changed,
            })

            (ok {
                token-id: token-id,
                new-level: new-level,
                new-experience: final-experience,
                level-up: level-changed,
            })
        )
    )
)

;; Helper function to calculate level based on experience
(define-private (calculate-level (experience uint))
    (if (>= experience u2000)
        u5
        (if (>= experience u1000)
            u4
            (if (>= experience u500)
                u3
                (if (>= experience u250)
                    u2
                    u1
                )
            )
        )
    )
)

;; Function to generate token URI with token ID
(define-private (generate-token-uri (token-id uint))
    (let ((id-string (get-token-id-string token-id)))
        (concat (var-get base-uri) id-string)
    )
)

;; Helper function to convert token ID to string (supports up to 999 tokens)
(define-private (get-token-id-string (token-id uint))
    (if (<= token-id u9)
        (unwrap-panic (element-at "123456789" (- token-id u1)))
        (if (<= token-id u99)
            (concat
                (unwrap-panic (element-at "123456789" (- (/ token-id u10) u1)))
                (unwrap-panic (element-at "0123456789" (mod token-id u10)))
            )
            (if (<= token-id u999)
                (concat
                    (concat
                        (unwrap-panic (element-at "123456789" (- (/ token-id u100) u1)))
                        (unwrap-panic (element-at "0123456789" (mod (/ token-id u10) u10)))
                    )
                    (unwrap-panic (element-at "0123456789" (mod token-id u10)))
                )
                "999"
            )
        )
    )
    ;; Fallback for tokens > 999
)

;; Read-only functions
(define-read-only (get-token-metadata (token-id uint))
    (map-get? token-metadata token-id)
)

(define-read-only (get-token-uri (token-id uint))
    (ok (some (generate-token-uri token-id)))
)

(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? dynamic-nft token-id))
)

(define-read-only (get-last-token-id)
    (ok (var-get last-token-id))
)

;; Owner functions
(define-public (set-base-uri (new-base-uri (string-ascii 256)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set base-uri new-base-uri)
        (ok true)
    )
)
