; 13 November 2001 / lth
;
; Routines for dumping a Petit Larceny heap image using
; Microsoft Visual C/C++ 6.0 (Standard Edition) under 
; Windows NT and Windows 2000 (at least).
;
; MSVC++ and its associated tools seem to have extremely
; silly ideas about where to look for debug information
; for .LIB files -- the linker always looks in VC60.PDB
; in the directory of the .LIB file.  (Or perhaps it is
; in the working directory?  The error messages are too
; obscure to decipher.)

(define win32/petit-rts-library "Rts\\petit-rts.lib")
(define win32/petit-lib-library "petit-lib.lib")
(define win32/petit-exe-name    "petit.exe")

(define (build-petit-larceny heap output-file-name input-file-names)
  (build-petit-lib-library input-file-names)
  ;(build-application win32/petit-exe-name '())
  )

(define (build-petit-lib-library input-file-names)
  (c-link-library win32/petit-lib-library
		  (remove-duplicates
		   (append (map (lambda (x)
				  (rewrite-file-type x ".lop" ".obj"))
				input-file-names)
			   (list (rewrite-file-type *temp-file* ".c" ".obj")))
		   string=?)
		  '()))

(define (build-application executable-name additional-files)
  (let ((src-name (rewrite-file-type executable-name '(".exe") ".c"))
        (obj-name (rewrite-file-type executable-name '(".exe") ".obj")))
    (init-variables)
    (for-each create-loadable-file additional-files)
    (dump-loadable-thunks src-name)
    (c-compile-file src-name obj-name)
    (c-link-executable executable-name
                       (cons obj-name
                             (map (lambda (x)
                                    (rewrite-file-type x ".lop" ".obj"))
                                  additional-files))
                       (list win32/petit-rts-library
			     win32/petit-lib-library))
    executable-name))

(define (create-indirect-file filename object-files)
  (delete-file filename)
  (call-with-output-file filename
    (lambda (out)
      (for-each (lambda (x)
		  (display x out)
		  (newline out))
		object-files))))

; Compiler definitions

; Microsoft Visual C/C++ 6.0

(define (c-compiler:msvc-win32 c-name o-name)
  (execute
   (twobit-format 
    #f
    "cl /nologo /c /Zp4 /Zd ~a /IRts\\Sys /IRts\\Standard-C /IRts\\Build /DSTDC_SOURCE ~a /Fo~a ~a"
    (if (optimize-c-code) "/O2" "")
    (if (optimize-c-code) "/DNDEBUG" "")
    o-name
    c-name)))

(define (c-library-linker:msvc-win32 output-name object-files libs)
  (let ((lnk-name (rewrite-file-type output-name ".lib" ".lnk"))
	(lib-name (rewrite-file-type output-name ".lib" "")))
    (create-indirect-file lnk-name object-files)
    (delete-file output-name)
    (execute
     (twobit-format #f "lib.exe /libpath:. /name:~a /out:~a @~a" lib-name output-name lnk-name))))

(define (c-dll-linker:msvc-win32 output-name object-files)
  ;; FIXME!!
  (create-indirect-file "petit-objs.lnk" object-files)
  (system "del vc60.pdb")
  (execute
   (twobit-format #f
		  "link.exe /dll /export:twobit_load_table /debug /out:~a @petit-objs.lnk petit.exe"
		  output-name)))

(define (c-linker:msvc-win32 output-name object-files libs)
  (create-indirect-file "petit-objs.lnk" object-files)
  (system "del vc60.pdb")
  (execute
   (twobit-format #f
		  "link.exe /debug /export:mc_alloc /out:~a @petit-objs.lnk ~a"
		  output-name
		  (apply string-append (insert-space libs)))))

; Metrowerks CodeWarrior 6.0

(define (c-compiler:mwcc-win32 c-name o-name)
  (execute
   (twobit-format 
    #f
    "mwcc -g -c ~a -IRts\\Sys -IRts\\Standard-C -IRts\\Build -DSTDC_SOURCE ~a -o ~a ~a"
    (if (optimize-c-code) "-opt full" "")  ; or -opt on
    (if (optimize-c-code) "-DNDEBUG" "")
    o-name
    c-name)))

(define (c-dll-linker:mwcc-win32 output-name object-files . ignored)
  (create-indirect-file "petit-objs.lnk" object-files)
  (execute
   (twobit-format #f
		  "mwld -noentry -shared -export sym=twobit_load_table -g -o ~a @petit-objs.lnk petit.lib"
		  output-name)))

(define-compiler 
  "Microsoft Visual C/C++ 6.0 on Win32" 
  'msvc
  ".obj"
  `((compile            . ,c-compiler:msvc-win32)
    (link-library       . ,c-library-linker:msvc-win32)
    (link-executable    . ,c-linker:msvc-win32)
    (link-shared-object . ,c-dll-linker:msvc-win32)
    (append-files       . ,append-file-shell-command-msdos)))

(define-compiler 
  "Metrowerks CodeWarrior C/C++ 6.0 on Win32"
  'mwcc
  ".obj"
  `((compile            . ,c-compiler:mwcc-win32)
    (link-library       . ,c-library-linker:msvc-win32)
    (link-executable    . ,c-linker:msvc-win32)
    (link-shared-object . ,c-dll-linker:mwcc-win32)
    (append-files       . ,append-file-shell-command-msdos)))

(select-compiler 'mwcc)

; eof

