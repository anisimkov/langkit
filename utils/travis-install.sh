#! /usr/bin/env sh

set -v
set -e

if ! [ -d $TOOLS_DIR ]
then
    mkdir -p $TOOLS_DIR
fi
if ! [ -d $INSTALL_DIR ]
then
    mkdir -p $INSTALL_DIR
fi

# Get and install GNAT
if ! [ -d gnat_community_install_script ]
then
    git clone https://github.com/AdaCore/gnat_community_install_script.git
else
    (cd gnat_community_install_script && git pull)
fi
if ! [ -f $INSTALL_DIR/bin/gcc ]
then
	GNAT_INSTALLER=$TOOLS_DIR/gnat-community-2018-20180528-x86_64-linux-bin
	GNAT_INSTALLER_URL=http://mirrors.cdn.adacore.com/art/5b0d7bffa3f5d709751e3e04

    wget -O $GNAT_INSTALLER $GNAT_INSTALLER_URL
    sh gnat_community_install_script/install_package.sh \
        "$GNAT_INSTALLER" "$INSTALL_DIR"
    $INSTALL_DIR/bin/gprinstall --uninstall gnatcoll
fi

# Get gnatcoll-core and gnatcoll-bindings
if [ -d "$TOOLS_DIR/gnatcoll-core" ]
then
    (cd $TOOLS_DIR/gnatcoll-core && git pull)
else
    (cd $TOOLS_DIR && git clone https://github.com/AdaCore/gnatcoll-core)
fi
if [ -d "$TOOLS_DIR/gnatcoll-bindings" ]
then
    (cd $TOOLS_DIR/gnatcoll-bindings && git pull)
else
    (cd $TOOLS_DIR && git clone https://github.com/AdaCore/gnatcoll-bindings)
fi

# Log content
pwd
export PATH=$INSTALL_DIR/bin:$PATH
which gcc
gcc -v

# Build gnatcoll-core
(
    cd $TOOLS_DIR/gnatcoll-core
    make PROCESSORS=0 prefix="$INSTALL_DIR" ENABLE_SHARED=yes \
       build install
)

# Build gnatcoll-bindings
(
    cd $TOOLS_DIR/gnatcoll-bindings
    for component in iconv gmp
    do
        (
            cd $component
            python setup.py build --reconfigure -j0 --prefix="$INSTALL_DIR" \
               --library-types=static,relocatable
            python setup.py install
        )
    done
)

# Install Langkit itself and its Python dependencies
pip install .
