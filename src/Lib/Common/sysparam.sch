; Copyright 1998 Lars T Hansen.
;
; $Id$
;
; Larceny library -- system parameter abstraction.

($$trace "sysparam")

; System parameters are defined in the Library using this procedure.
;
; Larceny's parameters pre-date SRFI 39, which is incompatible with
; Larceny's parameters.  The following definition has been modified
; to be almost compatible with SRFI 39.  The one remaining incompatibility
; occurs when the first argument is a string and the second a procedure.
; In that case, the ambiguity is resolved by using Larceny's semantics.

(define (make-parameter arg1 . rest)
  (let* ((srfi39-style? (or (null? rest)
                            (and (not (string? arg1))
                                 (not (symbol? arg1))
                                 (procedure? (car rest)))))
         (converter (if (and srfi39-style? (pair? rest))
                        (car rest)
                        values))
         (ok? (if (or (null? rest) (null? (cdr rest)))
                  (lambda (x) #t) 
                  (cadr rest)))
         (name (if srfi39-style? #f arg1))
         (value (if srfi39-style? (converter arg1) (car rest))))
    (define (complain-argcount)
      (assertion-violation name "too many arguments" (cons arg1 rest))
      #t)
    (define (complain-bad-value x)
      (assertion-violation name "invalid value for parameter" x)
      #t)
    (if srfi39-style?
        (lambda args
          (if (pair? args)
              (if (null? (cdr args))
                  (let ((new-value (converter (car args))))
                    (set! value new-value)
                    value)
                  (complain-argcount))
              value))
        (lambda args
          (if (pair? args)
              (if (null? (cdr args))
                  (let ((new-value (car args)))
                    (if (ok? new-value)
                        (begin (set! value new-value)
                               value)
                        (complain-bad-value (car args))))
                  (complain-argcount))
              value)))))

; Returns an assoc list of system information.

(define (system-features)
  (let* ((wordsize
	  (if (fixnum? (expt 2 32)) 64 32))
	 (char-bits
          (let ((c21 (integer->char #x100000))
                (c16 (integer->char #xffff)))
            (cond ((char=? c21 (string-ref (make-string 1 c21) 0))
                   32)
                  ((char=? c16 (string-ref (make-string 1 c16) 0))
                   16)
                  (else 8))))
	 (char-repr
	  (case char-bits
	    ((8)  'iso-latin-1)		; iso 8859/1
	    ((16) 'ucs2)		; 2-byte unicode (not supported)
	    ((32) 'unicode)		; all Unicode characters
	    (else 'unknown)))
         (string-repr
          (let ((s (make-string 1 #\space)))
            (cond ((bytevector-like? s)
                   (case (bytevector-like-length s)
                    ((1) 'flat1)
                    ((4) 'flat4)
                    (else 'unknown)))
                  ((vector-like? s)
                   'unknown)
                  (else 'unknown))))
	 (gc-info
	  (sys$system-feature 'gc-tech)))
    (list (cons 'larceny-major-version  (sys$system-feature 'larceny-major))
	  (cons 'larceny-minor-version  (sys$system-feature 'larceny-minor))
	  (cons 'arch-name              (sys$system-feature 'arch-name))
	  (cons 'arch-endianness        (sys$system-feature 'endian))
	  (cons 'arch-word-size         wordsize)
	  (cons 'os-name                (sys$system-feature 'os-name))
	  (cons 'os-major-version       (sys$system-feature 'os-major))
	  (cons 'os-minor-version       (sys$system-feature 'os-minor))
	  (cons 'fixnum-bits            (- wordsize 2))
	  (cons 'fixnum-representation  'twos-complement)
	  (cons 'codevector-representation (sys$system-feature 'codevec))
	  (cons 'char-bits              char-bits)
	  (cons 'char-representation    char-repr)
          (cons 'string-representation  string-repr)
	  (cons 'flonum-bits            64)
	  (cons 'flonum-representation  'ieee)
          (cons 'case-sensitivity       (not (sys$system-feature 'foldcase)))
          (cons 'transcoder             (sys$system-feature 'transcoder))
          (cons 'safety                 (sys$system-feature 'safety))
          (cons 'execution-mode         (sys$system-feature 'execmode))
          (cons 'ignore-first-line      (sys$system-feature 'ignore1))
          (cons 'pedantic               (sys$system-feature 'pedantic))
          (cons 'library-path           (sys$system-feature 'r6path))
          (cons 'top-level-program      (sys$system-feature 'r6program))
	  (cons 'gc-technology          (car gc-info))
	  (cons 'heap-area-info         (cdr gc-info)))))

; eof
