; Copyright 1991 Lightship Software, Incorporated.
;
; $Id$
;
; Larceny -- Print procedures.

($$trace "print")

;;; Parameterized hooks to customize the printer.
(define code-object-printer
  (make-parameter
   "code-object-printer"
   (lambda (co port slashify)
     (print (string-append "#<"
                           (car (vector-ref co 0))
                           ">")
            port
            #f))))

(define environment-printer
  (make-parameter
   "environment-printer"
   (lambda (environment port slashify)
     (print (string-append "#<ENVIRONMENT "
                           (environment-name environment)
                           ">")
            port
            #f))))

(define hashtable-printer
  (make-parameter
   "hashtable-printer"
   (lambda (hashtable port slashify)
     (print "#<HASHTABLE>" port #f))))

(define procedure-printer
  (make-parameter
   "procedure-printer"
   (lambda (procedure port slashify)
     (print (string-append "#<PROCEDURE"
                           (let ((doc (procedure-name procedure)))
                             (if doc
                                 (string-append " " (symbol->string doc))
                                 ""))
                           ">")
            port
            #f))))

(define weird-printer
  (make-parameter
   "weird-printer"
   (lambda (weirdo port slashify)
     (print "#<WEIRD OBJECT>" port #f))))

(define (print x p slashify)

  (define write-char io/write-char)

  (define quoters '(quote quasiquote unquote unquote-splicing
                    syntax quasisyntax unsyntax unsyntax-splicing))

  (define quoter-strings '((quote . "'")
			   (quasiquote . "`")
			   (unquote . ",")
			   (unquote-splicing . ",@")
                           (syntax . "#'")
			   (quasisyntax . "#`")
			   (unsyntax . "#,")
			   (unsyntax-splicing . "#,@")))

 ;FIXME: R6RS won't allow a backslash before semicolon
 ;(define funny-characters (list #\" #\\ #\;))

  (define funny-characters (list #\" #\\))

  (define ctrl-B (integer->char 2))
  (define ctrl-C (integer->char 3))
  (define ctrl-F (integer->char 6))

  ;; Which characters are written in hex and which are not
  ;; is completely implementation-dependent, so long as
  ;; get-datum can reconstruct the datum.
  ;;
  ;; Differences between this predicate and the rule for
  ;; hexifying the characters of an identifier:
  ;;     does not hexify Nd, Mc, or Me even at beginning of string
  ;;     does not hexify Ps, Pe, Pi, or Pf
  ;;     hexifies Co (private use)

  (define (print-in-string-without-hexifying? c)
    (let ((sv (char->integer c)))
      (or (<= 32 sv 126)
          (and (<= 128 sv)
               (not (memq (char-general-category c)
                          '(Zs Zl Zp Cc Cf Cs Co Cn)))))))

  ;; Same as above but also hexifies Mn, Mc, and Me.

  (define (print-as-char-without-hexifying? c)
    (let ((sv (char->integer c)))
      (or (<= 32 sv 126)
          (and (<= 128 sv)
               (not (memq (char-general-category c)
                          '(Mn Mc Me Zs Zl Zp Cc Cf Cs Co Cn)))))))

  ;; Don't print ellipsis when slashifying (that is, when
  ;; using WRITE rather than DISPLAY) because result is
  ;; being printed with intent to read it back in.

  (define (print x p slashify level)
    (cond ((and (not slashify)
                (zero? level))
           (printstr "..." p))
          ((not (pair? x)) (patom x p slashify level))
	  ((and (memq (car x) quoters)
		(pair? (cdr x))
		(null? (cddr x)))
	   (print-quoted x p slashify level))
          ((and (not slashify)
                (zero? (- level 1)))
           (printstr "(...)" p))
          ((and (not slashify)
                (eqv? 0 (print-length)))
           (printstr "(...)" p))
	  (else
           (write-char (string-ref "(" 0) p)
           (print (car x) p slashify (- level 1))
           (print-cdr (cdr x) p slashify
                      (- level 1)
                      (- (or (print-length) 0) 1)))))

  (define (print-cdr x p slashify level length)
    (cond ((null? x)
           (write-char (string-ref ")" 0) p))
          ((and (not slashify)
                (zero? length))
           (printstr " ...)" p))
          ((pair? x)
           (write-char #\space p)
           (print (car x) p slashify level)
           (print-cdr (cdr x) p slashify level (- length 1)))
          (else
	   (printstr " . " p)
           (patom x p slashify level)
           (write-char (string-ref ")" 0) p))))

  (define (printsym s p) (printstr s p))

  (define (printstr s p)

    (define (loop x p i n)
      (if (< i n)
	  (begin (write-char (string-ref x i) p)
		 (loop x p (+ 1 i) n))))

    (loop s p 0 (string-length s)))

  (define (print-slashed-symbol x p)

    (let* ((s (symbol->string x))
           (n (string-length s)))

      (define (loop i)
        (if (< i n)
            (let ((c (string-ref s i)))
              (cond ((or (and (char<=? #\a c) (char<=? c #\z))
                         (and (char<=? #\A c) (char<=? c #\Z))
                         (case c
                          ((#\! #\$ #\% #\& #\* #\/ #\: 
                            #\< #\= #\> #\? #\^ #\_ #\~)
                           ; special initial
                           #t)
                          ((#\0 #\1 #\2 #\3 #\4
                            #\5 #\6 #\7 #\8 #\9
                            #\@)
                           ; special subsequent
                           (< 0 i))
                          ((#\+ #\- #\.)
                           ; check for peculiar identifiers
                           (or (< 0 i)
                               (memq x '(+ - ...))
                               (and (char=? c #\-)
                                    (< (+ i 1) n)
                                    (char=? (string-ref s (+ i 1)) #\>))))
                          (else
                           (if (memq (transcoder-codec (port-transcoder p))
                                     '(utf-8 utf-16))
                               (let ((cat (char-general-category c)))
                                 (or (and (< 127 (char->integer c))
                                          (memq cat
                                                '(Lu Ll Lt Lm Lo Mn Nl No
                                                  Pd Pc Po Sc Sm Sk So Co)))
                                     (and (< 0 i)
                                          (memq cat '(Nd Mc Me)))))
                               #f))))
                     (write-char c p)
                     (loop (+ i 1)))
                    (else
                     (let ((hexstring (number->string (char->integer c) 16)))
                       (write-char #\\ p)
                       (write-char #\x p)
                       (print-slashed-string hexstring p)
                       (write-char #\; p)
                       (loop (+ i 1))))))))

      (loop 0)))

  (define (print-slashed-string s p)

    (define (loop i n)
      (if (< i n)
          (let* ((c (string-ref s i))
                 (sv (char->integer c)))
            (cond ((<= 32 sv 126)
                   (if (or (char=? c #\\)
                           (char=? c #\"))
                       (write-char #\\ p))
                   (write-char c p))
                  ((and (<= 128 sv)
                        (memq (transcoder-codec (port-transcoder p))
                              '(utf-8 utf-16))
                        (print-in-string-without-hexifying? c))
                   (write-char c p))
                  (else
                   (write-char #\\ p)
                   (case sv
                    ((7) (write-char #\a p))
                    ((8) (write-char #\b p))
                    ((9) (write-char #\t p))
                    ((10) (write-char #\n p))
                    ((11) (write-char #\v p))
                    ((12) (write-char #\f p))
                    ((13) (write-char #\r p))
                    (else
                     (let ((hexstring (number->string sv 16)))
                       (write-char #\x p)
                       (print-slashed-string hexstring p)
                       (write-char #\; p))))))
            (loop (+ i 1) n))))

    (loop 0 (string-length s)))

  (define (print-slashed-bytevector s p)

    (define (loop x p i n)
      (if (< i n)
	  (let ((c (integer->char (bytevector-ref x i))))
	    (if (memq c funny-characters)
		(write-char #\\ p))
	    (write-char c p)
	    (loop x p (+ 1 i) n))))

    (loop s p 0 (bytevector-length s)))

  (define (patom x p slashify level)
    (cond ((eq? x '())              (printstr "()" p))
	  ((not x)                  (printstr "#f" p))
	  ((eq? x #t)               (printstr "#t" p))
	  ((symbol? x)
           (if slashify
               (print-slashed-symbol x p)
               (printsym (symbol->string x) p)))
	  ((number? x)              (printnumber x p slashify))
	  ((char? x)
	   (if slashify
	       (printcharacter x p)
	       (write-char x p)))
	  ((string? x)
	   (if slashify
	       (begin (write-char #\" p)
		      (print-slashed-string x p)
		      (write-char #\" p))
	       (printstr x p)))

	  ((vector? x) (cond ((environment? x) (printenvironment x p slashify))
                             ((code-object? x) (printcodeobject x p slashify))
                             ((hashtable? x)   (printhashtable x p slashify))
                             (else (write-char #\# p)
                                   (print (vector->list x) p slashify level))))

	  ((procedure? x)           (printprocedure x p slashify))
	  ((bytevector? x)          (printbytevector x p slashify level))
	  ((eof-object? x)          (printeof x p slashify))
	  ((port? x)                (printport x p slashify))
	  ((eq? x (unspecified))    (printstr "#!unspecified" p))
	  ((eq? x (undefined))      (printstr "#!undefined" p))
	  ((structure? x)
	   ((structure-printer) x p slashify))
	  (else                     (printweird x p slashify))))

  (define (printnumber n p slashify)
    (if (eq? slashify **lowlevel**)
	(cond ((flonum? n)
	       (write-char #\# p)
	       (write-char ctrl-F p)
	       (do ((i 4 (+ i 1)))
		   ((= i 12))
		 (write-char (integer->char (bytevector-like-ref n i)) p)))
	      ((compnum? n)
	       (write-char #\# p)
	       (write-char ctrl-C p)
	       (do ((i 4 (+ i 1)))
		   ((= i 20))
		 (write-char (integer->char (bytevector-like-ref n i)) p)))
	      (else
	       (printstr (number->string n) p)))
	(printstr (number->string n) p)))

  (define (printcharacter c p)
    (write-char #\# p)
    (write-char #\\ p)
    (let ((k (char->integer c)))
      (cond ((<= k **space**)
             (cond ((= k **space**)  (printstr "space" p))
                   ((= k **newline**) (printstr "newline" p))
                   ((= k **linefeed**) (printstr "linefeed" p))
                   ((= k **return**) (printstr "return" p))
                   ((= k **tab**) (printstr "tab" p))
                   ((= k **nul**) (printstr "nul" p))
                   ((= k **alarm**) (printstr "alarm" p))
                   ((= k **backspace**) (printstr "backspace" p))
                   ((= k **vtab**) (printstr "vtab" p))
                   ((= k **page**) (printstr "page" p))
                   ((= k **esc**) (printstr "esc" p))
                   (else
                    (printstr "x" p)
                    (printstr (number->string k 16) p))))
            ((< k **delete**) (write-char c p))
            ((= k **delete**) (printstr "delete" p))
            ((and (memq (transcoder-codec (port-transcoder p))
                        '(utf-8 utf-16))
                  (print-as-char-without-hexifying? c))
             (write-char c p))
            (else
             (printstr "x" p)
             (printstr (number->string k 16) p)))))

  (define (printcodeobject x p slashify)
    ((code-object-printer) x p slashify))

  (define (printenvironment x p slashify)
    ((environment-printer) x p slashify))

  (define (printhashtable x p slashify)
    ((hashtable-printer) x p slashify))

  (define (printprocedure x p slashify)
    ((procedure-printer) x p slashify))

  (define (printbytevector x p slashify level)
    (if (eq? slashify **lowlevel**)
	(begin (write-char #\# p)
	       (write-char ctrl-B p)
	       (write-char #\" p)
	       (print-slashed-bytevector x p)
	       (write-char #\" p))
        (begin (write-char #\# p)
               (write-char #\v p)
               (write-char #\u p)
               (write-char #\8 p)
               (print (bytevector->list x) p slashify (- level 1)))))

  (define (printport x p slashify)
    (printstr (string-append "#<" (cond ((input-port? x) "INPUT PORT ")
					((output-port? x) "OUTPUT PORT ")
					(else "PORT "))
			     (port-name x)
			     ">")
	      p))

  (define (printeof x p slashify)
    (printstr "#<EOF>" p))

  (define (printweird x p slashify)
    ((weird-printer) x p slashify))

  (define (print-quoted x p slashify level)
    (printstr (cdr (assq (car x) quoter-strings)) p)
    (print (cadr x) p slashify (- level 1)))

  (print x p slashify (+ (or (print-level) -2) 1)))

(define print-length
  (let ((*print-length* #f))
    (lambda rest
      (cond ((null? rest) *print-length*)
            ((null? (cdr rest))
             (let ((x (car rest)))
               (if (not (or (not x)
                            (and (fixnum? x) (>= x 0))))
                   (error "Bad argument " x " to print-length."))
               (set! *print-length* x)
               x))
            (else
             (error "Wrong number of arguments to print-length."))))))

(define print-level
  (let ((*print-level* #f))
    (lambda rest
      (cond ((null? rest) *print-level*)
            ((null? (cdr rest))
             (let ((x (car rest)))
               (if (not (or (not x)
                            (and (fixnum? x) (>= x 0))))
                   (error "Bad argument " x " to print-level."))
               (set! *print-level* x)
               x))
            (else
             (error "Wrong number of arguments to print-level."))))))

(define **lowlevel** (list 0))   ; any unforgeable value

(define **nonprinting-value** (unspecified))

(define write
  (lambda (x . rest)
    (let ((p (if (pair? rest) (car rest) (current-output-port))))
      (print x p #t)
      (io/discretionary-flush p)
      **nonprinting-value**)))

(define display
  (lambda (x . rest)
    (let ((p (if (pair? rest) (car rest) (current-output-port))))
      (print x p #f)
      (io/discretionary-flush p)
      **nonprinting-value**)))

(define lowlevel-write
  (lambda (x . rest)
    (let ((p (if (pair? rest) (car rest) (current-output-port))))
      (print x p **lowlevel**)
      (io/discretionary-flush p)
      **nonprinting-value**)))

(define newline
  (lambda rest
    (let ((p (if (pair? rest) (car rest) (current-output-port))))
      (write-char #\newline p)
      (io/discretionary-flush p)
      **nonprinting-value**)))

; eof
