(lang dune 3.7)

(name tanenbaum)
(version 0.3.0)

(generate_opam_files true)

(source
 (github baffalop/tanenbaum))

(authors "Sixstring982" "baffalop")

(maintainers "Sixstring982" "baffalop")

(license BSD-3-Clause)

(documentation https://github.com/baffalop/tanenbaum)

(package
 (name tanenbaum)
 (synopsis "OCaml Advent of Code starter project")
 (depends
  ocaml
  reason
  dune
  (cmdliner(>= 1.2.0))
  ezcurl
  (fmt (>= 0.9.0)))
 (tags ("advent-of-code")))
