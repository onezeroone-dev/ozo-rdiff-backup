# Set variables
NAME="onezeroone-release"
VERSION="1.0.0"
ARCH="noarch"
OSRELE="10"
PKRELE="1"
VARTMP="/var/tmp"
TMPDIR="$VARTMP/$NAME-$VERSION"
SOURCESDIR="/srv/rpmbuild/SOURCES"
SPECSDIR="/srv/rpmbuild/SPECS"
SPECFILE="onezeroone-release.spec"
SPECPATH="$SPECSDIR/$SPECFILE"
TARPATH="$SOURCESDIR/$NAME-$VERSION.tar.gz"
RPMSPATH="/srv/rpmbuild/RPMS"
RPMPATH="$RPMSPATH/$ARCH/$NAME-$VERSION-$PKRELE.el$OSRELE.$ARCH.rpm"

# Create a temporary directory
mkdir -p $TMPDIR

# Copy in file assets
cp onezeroone.repo $TMPDIR
cp onezeroone-test.repo $TMPDIR
cp RPM-GPG-KEY-ONEZEROONE $TMPDIR

# If the tarball exists
if [[ -f $TARPATH ]]
then
    # remove it
    rm -f $TARPATH
fi

# Create a gzipped tarball in SOURCES
tar cfvz $TARPATH -C $VARTMP "$NAME-$VERSION"

# Remove the temporary directory
rm -rf $TMPDIR

# If the spec file exists
if [[ -f "$SPECPATH/" ]]
then
    # remove it
    rm -f $SPECPATH
fi

# Copy the spec file to SPECS
cp $SPECFILE $SPECSDIR

# Determine if spec passes linting test
cd ~
if rpmlint $SPECPATH
then
   # Determine if the source RPM builds
   if rpmbuild -bs $SPECPATH
   then
        # Determine if the RPM builds
        if rpmbuild -bb $SPECPATH
        then
            # Sign the RPM
            rpm --addsign $RPMPATH
        fi
   fi
fi
cd -
