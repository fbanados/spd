#lang racket
(require (for-syntax racket/base syntax/parse racket/list racket/function
                     stepper/private/syntax-property))

;; Syntax for @tags.
;;
;; @tags are checked for well-formedness and some reference checks during
;; syntax expansion, they expand to just (void) so that they don't
;; affect what values are printed when student code is run.
;; 
;; The file structure parser pulls apart the syntax later, knowing the
;; tags are are well-formed.

(provide @Problem 

         @HtDW      
         @HtDD      
         @HtDF      
          
         @dd-template-rules 
         @template)


(define-for-syntax PRIMITIVE-TYPES
  '(Number Integer Natural String Boolean Image Color Scene
           KeyEvent MouseEvent
           1String))

(define-for-syntax DD-TEMPLATE-RULES
  '(atomic-non-distinct atomic-distinct one-of compound self-ref ref))

(define-for-syntax TEMPLATE-ORIGINS
  '(;<TypeName>      decomposition and possible structural recursion
    add-param        ;used once for 1 or more atomic params
    htdw-main    
    fn-composition   ;used once for composition of 2 or more fns
    backtracking     
    2-one-of
    encapsulated
    use-abstract-fn
    genrec
    bin-tree         ;should be used w/ genrec
    arb-tree         ;should be used w/ genrec
    accumulator
    for-each))

(define-for-syntax TAGS empty)     ;(listof Syntax)  built in expansion phase 0
(define-for-syntax PROBLEMS empty) ;(listof Natural) built in expansion phase 1


(define-for-syntax (stepper-void)  
  (with-stepper-syntax-properties (['stepper-skip-completely #t])
                                  #'(void)))


;; Sets up 2 phase expansion.  First phase is basic syntax, second phase checks
;; that referenced functions are bound, problem numbers aren't duplicated etc.
(define-syntax (define-@Tag-syntax stx)
  (syntax-case stx ()
    [(_ tag arity-string kind-string checker)     
     #`(define-syntax (tag stx)         
         (unless (member (syntax-local-context) '(module top-level))            
           (raise-syntax-error #f (format "Found ~a that is not at top level" 'tag) stx))         
         (syntax-case stx ()
           [(_)        (raise-syntax-error #f (format "expected ~a ~a after ~a" arity-string kind-string 'tag) stx)]
           [(_ . id)   (set! TAGS (cons stx TAGS)) (with-stepper-syntax-properties (['stepper-skip-completely #t]) #'(#%expression (checker . id)))]
           [_          (raise-syntax-error #f (format "expected an open parenthesis before ~a" 'tag) stx)]))]))
                                             

(define-@Tag-syntax @Problem                    "one" "integer greater than 0"    check-problem)
(define-@Tag-syntax @HtDF              "at least one" "function name"             check-htdf)
(define-@Tag-syntax @HtDD              "at least one" "type name"                 check-htdd)
(define-@Tag-syntax @HtDW                       "one" "type name"                 check-htdw) 
(define-@Tag-syntax @template          "at least one" "template origin"           check-template)
(define-@Tag-syntax @dd-template-rules "at least one" "data driven template rule" check-dd-template-rules)


(define-syntax (check-problem stx)
  (syntax-case stx ()
    [(_ ns)
     (let ([n (syntax-e #'ns)])
       (unless (and (integer? n)
                    (> n 0))
         (raise-syntax-error '@Problem "expected integer 1 or greater." stx #'ns))
       (when (member n PROBLEMS)
         (raise-syntax-error '@Problem (format "problem number ~a was used previously and cannot be re-used" n) stx #'ns))
       (cond [(empty? PROBLEMS)
              (unless (= n 1)
                (raise-syntax-error '@Problem "expected first @Problem tag in file to be number 1" stx #'ns))]
             [(not (= n (add1 (first PROBLEMS))))
              (raise-syntax-error '@Problem
                                  (format "previous @Problem tag is number ~a, expected this one to be number ~a"
                                          (first PROBLEMS)
                                          (add1 (first PROBLEMS)))
                                  stx
                                  #'ns)])
       (set! PROBLEMS (cons n PROBLEMS))
       (stepper-void))]))

(define-syntax (check-htdf stx)    
  (syntax-case stx ()
    [(_ i ...)
     (for ([id-stx (syntax-e #'(i ...))])
          (let ([id (syntax-e id-stx)])
            (cond [(not (symbol? id))
                   (raise-syntax-error '@HtDF (format "~a is not a function name" id) stx id-stx)]
                  [(not (identifier-binding id-stx 0 #t))
                   (raise-syntax-error id "this function is not defined" stx id-stx)])))

     (stepper-void)]))

(define-syntax (check-htdd stx)    
  (syntax-case stx ()
    [(_ i ...)
     (for ([id-stx (syntax-e #'(i ...))])
          (let ([id (syntax-e id-stx)])
            (cond [(not (symbol? id))
                   (raise-syntax-error '@HtDD (format "~a is not a type name" id) stx id-stx)]
                  [(and (not (member id PRIMITIVE-TYPES))
                        (not (lookup-HtDD id)))
                   (raise-syntax-error '@HtDD (format "~A is not a primitive type and also cannot find @HtDD definition for it" id) stx id-stx)]
                  )))

     (stepper-void)]))

(define-syntax (check-htdw stx)    
  (syntax-case stx ()
    [(_ stx)
     (let ([type (syntax->datum #'stx)])
       (cond [(looks-like-type-name? type)
              (check-type '@HtDW #'stx type)]
             [else
              (raise-syntax-error '@HtDW (format "~a is not a type name" type) #'stx #'stx)]))

     (stepper-void)]))

(define-syntax (check-template stx)    
  (syntax-case stx ()
    [(_ t ...)
     (let* ([t-stxs (syntax-e #'(t ...))]
            [ts     (map syntax->datum t-stxs)])
       (for ([stx  t-stxs]
             [type ts])
            (cond [(looks-like-type-name? type) (check-type '@template stx type)]
                  [(symbol? type)
                   (when (not (member type TEMPLATE-ORIGINS))
                    (raise-syntax-error '@template
                                        (format "~a is neither a legal type name nor one of ~s" type (format-list TEMPLATE-ORIGINS #t)) stx stx))
                   (when (and (member type '(bin-tree arb-tree))
                              (not (member 'genrec ts)))
                     (raise-syntax-error '@template
                                         (format "using ~a requires also using genrec" type) stx stx))]
                  [else
                   (raise-syntax-error '@template (format "~a should be a TypeName or one of ~s." type TEMPLATE-ORIGINS) stx stx)])))
     (stepper-void)]))


(define-for-syntax (check-type who stx type)
  (if (and (list? type)
              (= (length type) 2)
              (eqv? (first type) 'listof))
         (check-type who stx (second type))
         (when (and (not (member type PRIMITIVE-TYPES))
                    (not (lookup-HtDD type))
                    (not (and (symbol? type)
                              (= (string-length (symbol->string type)) 1))))

           (raise-syntax-error who
                            (format "~a is not a primitive type, cannot find an @HtDD tag for it, and it is not a type parameter" type)
                            stx stx))))

(define-syntax (check-dd-template-rules stx)    
  (syntax-case stx ()
    [(_ i ...)
     (for ([id-stx (syntax-e #'(i ...))])
          (let ([id (syntax-e id-stx)])
            (cond [(not (member id DD-TEMPLATE-RULES))
                   (raise-syntax-error '@dd-template-rules (format "~a is not one of ~a" id (format-list DD-TEMPLATE-RULES #t)) stx id-stx)])))

     (stepper-void)]))

(define-for-syntax (lookup-HtDD id) 
  (let loop ([tags TAGS])
    (if (empty? tags)
        #f
        (let* ([t (first tags)]
               [d (syntax->datum t)])
          (if (and (eqv? (first d) '@HtDD)
                   (member id (rest d)))
              t
              (loop (rest tags)))))))

(define-for-syntax (format-list l or?)
  (cond [(empty? (rest l))
         (format "~a ~a" (if or? "or" "and") (first l))]
        [else
         (format "~a, ~a" (first l) (format-list (rest l) or?))]))

(define-for-syntax (looks-like-type-name? x)
  (or (and (symbol? x) (char-upper-case? (string-ref (symbol->string x) 0)))
      (and (list? x)
           (= (length x) 2)
           (eqv? (first x) 'listof))))

                   


