;  This is adapted from a benchmark written by John Ellis and Pete Kovac
;  of Post Communications.
;  It was modified by Hans Boehm of Silicon Graphics.
;  It was translated into Scheme by William D Clinger of Northeastern Univ;
;    the Scheme version uses (RUN-BENCHMARK <string> <thunk>)
;  It was later hacked by Lars T Hansen of Northeastern University,
;    and again by Clinger.
;
;  Modified 2000-02-15 / lth: changed gc-benchmark to only stretch once,
;     and to have a different interface (now accepts iteration numbers,
;     not tree height)
;  Last modified 2000-07-14 / lth -- fixed a buggy comment about storage 
;     use in Larceny.
;  Modified sometime by someone to accept both the number of iterations
;     and the tree height as optional arguments.
;  Modified 2011-05-29 / wdc: A regional collector requires large
;     arrays to be broken up into smaller pieces, so it's simulated
;     in this benchmark.
;
;       This is no substitute for real applications.  No actual application
;       is likely to behave in exactly this way.  However, this benchmark was
;       designed to be more representative of real applications than other
;       Java GC benchmarks of which we are aware.
;       It attempts to model those properties of allocation requests that
;       are important to current GC techniques.
;       It is designed to be used either to obtain a single overall performance
;       number, or to give a more detailed estimate of how collector
;       performance varies with object lifetimes.  It prints the time
;       required to allocate and collect balanced binary trees of various
;       sizes.  Smaller trees result in shorter object lifetimes.  Each cycle
;       allocates roughly the same amount of memory.
;       Two data structures are kept around during the entire process, so
;       that the measured performance is representative of applications
;       that maintain some live in-memory data.  One of these is a tree
;       containing many pointers.  The other is a large array containing
;       double precision floating point numbers.  Both should be of comparable
;       size.
; 
;       The results are only really meaningful together with a specification
;       of how much memory was used.  It is possible to trade memory for
;       better time performance.  This benchmark should be run in a 32 MB
;       heap, though we don't currently know how to enforce that uniformly.

; In the Java version, this routine prints the heap size and the amount
; of free memory.  There is no portable way to do this in Scheme; each
; implementation needs its own version.

(define (PrintDiagnostics)
  (display " Total memory available= ???????? bytes")
  (display "  Free memory= ???????? bytes")
  (newline))

(define (yes answer) #t)

; Should we implement a Java class as procedures or hygienic macros?
; Take your pick.

(define-syntax let-class
  (syntax-rules
   ()
   ; Put this rule first to implement a class using hygienic macros.
   ((let-class (((method . args) . method-body) ...) . body)
    (letrec-syntax ((method (syntax-rules () 
                              ((method . args) (begin . method-body))))
                    ...)
      . body))
   ; Put this rule first to implement a class using procedures.
   ((let-class (((method . args) . method-body) ...) . body)
    (let () (define (method . args) . method-body) ... . body))
   ))
                          

(define stretch #t)                ; Controls whether stretching phase is run

(define (gcbench kStretchTreeDepth)
  
  ; Use for inner calls to reduce noise.

  (define (run-benchmark name iters thunk test)
    (do ((i 0 (+ i 1)))
        ((= i iters))
      (thunk)))

  ;  Nodes used by a tree of a given size
  (define (TreeSize i)
    (- (expt 2 (+ i 1)) 1))
  
  ;  Number of iterations to use for a given tree depth
  (define (NumIters i)
    (quotient (* 2 (TreeSize kStretchTreeDepth))
              (TreeSize i)))
  
  ;  Parameters are determined by kStretchTreeDepth.
  ;  In Boehm's version the parameters were fixed as follows:
  ;    public static final int kStretchTreeDepth    = 18;  // about 16Mb
  ;    public static final int kLongLivedTreeDepth  = 16;  // about 4Mb
  ;    public static final int kArraySize  = 500000;       // about 4Mb
  ;    public static final int kMinTreeDepth = 4;
  ;    public static final int kMaxTreeDepth = 16;
  ;  wdc: In Larceny the storage numbers above would be 12 Mby, 3 Mby, 6 Mby.
  ;  lth: No they would not.  A flonum requires 16 bytes, so the size
  ;  of array + flonums would be 500,000*4 + 500,000*16=10 Mby.

  (let* ((kLongLivedTreeDepth (- kStretchTreeDepth 2))
         (kArraySize          (* 4 (TreeSize kLongLivedTreeDepth)))
         (kMinTreeDepth       4)
         (kMaxTreeDepth       kLongLivedTreeDepth))
    
    ; Elements 3 and 4 of the allocated vectors are useless.
    
    (let-class (((make-node l r)
                 (let ((v (make-empty-node)))
                   (vector-set! v 0 l)
                   (vector-set! v 1 r)
                   v))
                ((make-empty-node) (make-vector 4 0))
                ((node.left node) (vector-ref node 0))
                ((node.right node) (vector-ref node 1))
                ((node.left-set! node x) (vector-set! node 0 x))
                ((node.right-set! node x) (vector-set! node 1 x)))
      
      ;  Build tree top down, assigning to older objects.
      (define (Populate iDepth thisNode)
        (if (<= iDepth 0)
            #f
            (let ((iDepth (- iDepth 1)))
              (node.left-set! thisNode (make-empty-node))
              (node.right-set! thisNode (make-empty-node))
              (Populate iDepth (node.left thisNode))
              (Populate iDepth (node.right thisNode)))))
      
      ;  Build tree bottom-up
      (define (MakeTree iDepth)
        (if (<= iDepth 0)
            (make-empty-node)
            (make-node (MakeTree (- iDepth 1))
                       (MakeTree (- iDepth 1)))))
      
      (define (TimeConstruction depth)
        (let ((iNumIters (NumIters depth)))
          (display (string-append "Creating "
                                  (number->string iNumIters)
                                  " trees of depth "
                                  (number->string depth)))
          (newline)
          (run-benchmark "GCBench: Top down construction"
                         1
                         (lambda ()
                           (do ((i 0 (+ i 1)))
                               ((>= i iNumIters))
                               (Populate depth (make-empty-node))))
                         yes)
          (run-benchmark "GCBench: Bottom up construction"
                         1
                         (lambda ()
                           (do ((i 0 (+ i 1)))
                               ((>= i iNumIters))
                               (MakeTree depth)))
                         yes)))
      
      (define (main)

        ;; These definitions isolate the vector operations below
        ;; from those provided by the host system.

        (define (make-vector n x) (alternative-make-vector n x))
        (define (vector-length v) (alternative-vector-length v))
        (define (vector-ref v i) (alternative-vector-ref v i))
        (define (vector-set! v i x) (alternative-vector-set! v i x))

        (display "Garbage Collector Test")
        (newline)
        (if stretch
            (begin
              (display (string-append
                        " Stretching memory with a binary tree of depth "
                        (number->string kStretchTreeDepth)))
              (newline)))
        (PrintDiagnostics)
        (run-benchmark "GCBench: Main"
                       1
                       (lambda ()
                         ;  Stretch the memory space quickly
                         (if stretch
                             (MakeTree kStretchTreeDepth))
                         
                         ;  Create a long lived object
                         (display 
                          (string-append
                           " Creating a long-lived binary tree of depth "
                           (number->string kLongLivedTreeDepth)))
                         (newline)
                         (let ((longLivedTree (make-empty-node)))
                           (Populate kLongLivedTreeDepth longLivedTree)
                           
                           ;  Create long-lived array, filling half of it
                           (display (string-append
                                     " Creating a long-lived array of "
                                     (number->string kArraySize)
                                     " inexact reals"))
                           (newline)
                           (let ((array (make-vector kArraySize 0.0)))
                             (do ((i 0 (+ i 1)))
                                 ((>= i (quotient kArraySize 2)))
                                 (vector-set! array i 
                                              (/ 1.0 (exact->inexact i))))
                             (PrintDiagnostics)
                             
                             (do ((d kMinTreeDepth (+ d 2)))
                                 ((> d kMaxTreeDepth))
                                 (TimeConstruction d))
                             
                             (if (or (eq? longLivedTree '())
                                     (let ((n (min 1000
                                                   (- (quotient (vector-length array)
                                                                2)
                                                      1))))
                                       (not (= (vector-ref array n)
                                               (/ 1.0 (exact->inexact n))))))
                                 (begin (display "Failed") (newline)))
                             ;  fake reference to LongLivedTree
                             ;  and array
                             ;  to keep them from being optimized away
                             )))
                       yes)
        (PrintDiagnostics))
      
      (main))))

(define (gc-benchmark . rest)
  (let ((n (if (null? rest) 1 (car rest)))
        (k (if (or (null? rest) (null? (cdr rest))) 18 (cadr rest))))
    (display "The garbage collector should touch about ")
    (display (expt 2 (- k 13)))
    (display " megabytes of heap storage.")
    (newline)
    (display "The use of more or less memory will skew the results.")
    (newline)
    (set! stretch #t)
    (run-benchmark (string-append "GCBench:" (number->string n) ":" 
                                  (number->string k))
                   n
                   (lambda () 
                     (gcbench k)
                     (set! stretch #f))
                   yes)
    (set! stretch #t)))

;;; A regional collector may use an alternative representation
;;; for large vectors (so each allocated object will fit into
;;; a single region).

(define elements-per-arraylet (expt 2 16))

(define (alternative-make-vector n x)
  (let* ((n0 (div n elements-per-arraylet))
         (n1 (mod n elements-per-arraylet))
         (n00 (if (zero? n1) n0 (+ n0 1)))
         (v (make-vector n00)))
    (do ((i 0 (+ i 1)))
        ((= i n0))
      (vector-set! v i (make-vector elements-per-arraylet x)))
    (if (> n00 n0)
        (vector-set! v n0 (make-vector n1 x)))
    v))

(define (alternative-vector-length v)
  (let ((n (vector-length v)))
    (+ (* (- n 1) elements-per-arraylet)
       (vector-length (vector-ref v (- n 1))))))

(define (alternative-vector-ref v i)
  (let ((j (div i elements-per-arraylet))
        (k (mod i elements-per-arraylet)))
    (vector-ref (vector-ref v j) k)))

(define (alternative-vector-set! v i x)
  (let ((j (div i elements-per-arraylet))
        (k (mod i elements-per-arraylet)))
    (vector-set! (vector-ref v j) k x)))

