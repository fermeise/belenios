#!/bin/sh

set -e

# Check that OCamlDuce is not installed
if which ocamlduce >/dev/null; then
    echo "Please uninstall OCamlDuce first, or remove it from your PATH."
    exit 1
fi

export BELENIOS_SYSROOT="${BELENIOS_SYSROOT:-$HOME/.belenios}"
export OPAMROOT="$BELENIOS_SYSROOT/opam"

if [ -e "$BELENIOS_SYSROOT" ]; then
    echo "$BELENIOS_SYSROOT already exists."
    echo "Please remove it or set BELENIOS_SYSROOT to a non-existent directory first."
    exit 1
fi

mkdir -p "$BELENIOS_SYSROOT/bootstrap/src"

echo
echo "=-=-= Download and check tarballs =-=-="
echo
cd "$BELENIOS_SYSROOT/bootstrap/src"
wget http://caml.inria.fr/pub/distrib/ocaml-4.01/ocaml-4.01.0.tar.gz
wget http://www.ocamlpro.com/pub/opam-full-1.1.0.tar.gz
sha256sum --check <<EOF
ea1751deff454f5c738d10d8a0ad135afee0852d391cf95766b726c0faf7cfdb  ocaml-4.01.0.tar.gz
c0ab5e85b6cd26e533a40686e08aea173387d15bead817026f5b08f264642583  opam-full-1.1.0.tar.gz
EOF

echo
echo "=-=-= Compilation and installation of OCaml =-=-="
echo
cd "$BELENIOS_SYSROOT/bootstrap/src"
tar -xzf ocaml-4.01.0.tar.gz
cd ocaml-4.01.0
./configure -prefix "$BELENIOS_SYSROOT/bootstrap"
make world
make opt
make opt.opt
make install
export PATH="$BELENIOS_SYSROOT/bootstrap/bin:$PATH"

echo
echo "=-=-= Compilation and installation of OPAM =-=-="
echo
cd "$BELENIOS_SYSROOT/bootstrap/src"
tar -xzf opam-full-1.1.0.tar.gz
cd opam-full-1.1.0
./configure -prefix "$BELENIOS_SYSROOT/bootstrap"
make
make install

echo
echo "=-=-= Initialization of OPAM root =-=-="
echo
opam init --no-setup
eval `opam config env`

echo
echo "=-=-= Installation of Belenios build-dependencies =-=-="
echo
opam install --yes atdgen zarith cryptokit uuidm calendar eliom csv

echo
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
echo
echo "Belenios build-dependencies have been successfully compiled and installed"
echo "to $BELENIOS_SYSROOT. The directory"
echo "  $BELENIOS_SYSROOT/bootstrap/src"
echo "can be safely removed now."
echo
echo "Next, you need to run the following commands or add them to your ~/.bashrc"
echo "or equivalent:"
echo "  export PATH=$BELENIOS_SYSROOT/bootstrap/bin:\$PATH"
echo "  export OPAMROOT=$OPAMROOT"
echo "  eval \`opam config env\`"
echo
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
echo