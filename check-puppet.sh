#!/bin/bash
# Upstream original:
#   https://github.com/gini/puppet-git-hooks
# Upstream author:
#   Daniel Kerwin <hello@gini.net>
# License: Apache License Version 2.0 <https://raw.githubusercontent.com/gini/puppet-git-hooks/master/LICENSE-2.0.txt>
#
# Modified by Mikael Löfstrand <micke@lofstrand.net> for command line usage.
#
# External requirements:
#
#    * sed
#    * Ruby with ERB and YAML support
#    * Puppet >= 2.7
#    * puppet-lint
#
#    Adjust LINTFLAGS as appropriate

# Redirect output to stderr.
exec 1>&2

PUPPETLINT_FLAGS=${PUPPETLINT_FLAGS:-'--no-autoloader_layout-check --no-80chars-check'}
TMPDIR=${TMPDIR:-'/tmp'}
TMPFILE=$(mktemp "${TMPDIR}"/tmp.XXXXXXXXXX)
STATUS=0

# Register exit trap for removing temporary files
trap 'rm -rf $TMPFILE' EXIT INT HUP

# Check for ruby binary
which ruby >/dev/null 2>&1 || exit 1

# Check for Puppet binary
which puppet >/dev/null 2>&1 || exit 1

# Check for puppet-lint
which puppet-lint >/dev/null 2>&1 || exit 1

# Check for erb
which erb >/dev/null 2>&1 || exit 1

IFS="
 "

# Get a list of files changed in this transaction
declare -a FILES
FILES=$(find . -type f -name "*.pp" -or -name "*.erb" -or -name "*.yaml" -or -name "*.yml" -or -name "*.json")

for file in ${FILES[@]}
do
    # Don't check empty files
    if [[ $(cat "${file}" | wc -l) -eq 0 ]]; then
        continue
    fi

    extension="${file##*.}"
    cat "${file}" > $TMPFILE

    if [[ $? -ne 0 ]]; then
        echo "Unable to checkout ${file}"
        STATUS=2
    else
        case $extension in
            pp)
                # Remove import lines while parsing
                # http://projects.puppetlabs.com/issues/9670#note-14
                sed -i -e '/^import / d' $TMPFILE >/dev/null 2>&1
                # Puppet syntax check
                puppet parser validate $TMPFILE >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    echo "Puppet syntax error in ${file}. Run 'puppet parser validate ${file}'" >&2
                    STATUS=2
                fi

                # puppet-lint check
                puppet-lint $PUPPETLINT_FLAGS --log-format "${file}:%{linenumber} %{KIND} - %{message}" $TMPFILE 2> /dev/null
                if [[ $? -ne 0 ]] ; then
                    STATUS=2
                fi
            ;;
    
            erb)
                # syntax check templates - this doesn't catch a lot of mistakes,
                # but it should catch gross mistakes
                erb -x -T - "${TMPFILE}" | ruby -c >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    echo "ERB syntax error in ${file}" >&2
                    STATUS=2
                fi
            ;;
            yml|yaml)
                # syntax YAML files, https://ttboj.wordpress.com/2013/08/25/finding-yaml-errors-in-puppet/
                ruby -ryaml -e "YAML.parse(File.open('${TMPFILE}'))" >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    echo "YAML syntax error in ${file}" >&2
                    STATUS=2
                fi
            ;;
            json)
                # syntax JSON files, https://ttboj.wordpress.com/2013/08/25/finding-yaml-errors-in-puppet/
                ruby -rjson -e "JSON.parse(File.open('${TMPFILE}').read)" >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    echo "JSON syntax error in ${file}" >&2
                    STATUS=2
                fi
            ;;
        esac
    fi
done

exit $STATUS
