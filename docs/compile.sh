#!/bin/sh
set -eu
cd "$(dirname "$0")"
lualatex -interaction=nonstopmode -halt-on-error Genrmination_Fight.tex > compile-pass1.txt
lualatex -interaction=nonstopmode -halt-on-error Genrmination_Fight.tex > compile-pass2.txt
lualatex -interaction=nonstopmode -halt-on-error Genrmination_Fight.tex > compile-pass3.txt
