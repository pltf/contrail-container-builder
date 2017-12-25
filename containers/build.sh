#!/bin/bash
# Builds containers. Parses common.env to take CONTRAIL_REGISTRY, CONTRAIL_REPOSITORY, CONTRAIL_VERSION or takes them from
# environment.
# Parameters:
# path: relative path (from this directory) to module(s) for selective build. Example: ./build.sh controller/webui
#   if it's omitted then script will build all
#   "all" as argument means build all. It's needed if you want to build all and pass some docker opts (see below).
#   "list" will list all relative paths for build in right order. It's needed for automation. Example: ./build.sh list | grep -v "^INFO:"
# opts: extra parameters to pass to docker. If you want to pass docker opts you have to specify 'all' as first param (see 'path' argument above)

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../parse-env.sh"

path="$1"
shift
opts="$@"

echo "INFO: Contrail version: $version"
echo "INFO: OpenStack version: $os_version"
echo "INFO: OpenStack subversion (minor package version): $os_subversion"
echo "INFO: Contrail registry: $registry"
echo "INFO: Contrail repository: $repository"
if [ -n "$opts" ]; then
  echo "INFO: Options: $opts"
fi

linux=$(awk -F"=" '/^ID=/{print $2}' /etc/os-release | tr -d '"')
was_errors=0
op='build'

process_container () {
  local dir=${1%/}
  if [[ $op == 'list' ]]; then
    echo "${dir#"./"}"
    return
  fi
  local container_name=`echo ${dir#"./"} | tr "/" "-"`
  local container_name="contrail-${container_name}"
  echo "INFO: Building $container_name"
  if [ $linux == "centos" ]; then
    cat $dir/Dockerfile \
      | sed -e 's/\(^ARG CONTRAIL_REGISTRY=.*\)/#\1/' \
      -e 's/\(^ARG CONTRAIL_VERSION=.*\)/#\1/' \
      -e 's/\(^ARG OPENSTACK_VERSION=.*\)/#\1/' \
      -e 's/\(^ARG OPENSTACK_SUBVERSION=.*\)/#\1/' \
      -e "s/\$OPENSTACK_VERSION/$os_version/g" \
      -e "s/\$OPENSTACK_SUBVERSION/$os_subversion/g" \
      -e 's|^FROM ${CONTRAIL_REGISTRY}/\([^:]*\):${CONTRAIL_VERSION}-${OPENSTACK_VERSION}|FROM '${registry}'/\1:'${version}-${os_version}'|' \
      > $dir/Dockerfile.nofromargs
    int_opts="-f $dir/Dockerfile.nofromargs"
  fi
  local logfile='build-'$container_name'.log'
  docker build -t ${registry}'/'${container_name}:${version}-${os_version} \
    --build-arg CONTRAIL_VERSION=${version} \
    --build-arg OPENSTACK_VERSION=${os_version} \
    --build-arg OPENSTACK_SUBVERSION=${os_subversion} \
    --build-arg CONTRAIL_REGISTRY=${registry} \
    ${int_opts} ${opts} $dir |& tee $logfile
  if [ ${PIPESTATUS[0]} -eq 0 ]; then
    docker push ${registry}'/'${container_name}:${version}-${os_version} |& tee -a $logfile
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
      rm $logfile
    fi
  fi
  if [ -f $logfile ]; then
    was_errors=1
  fi
}

process_dir () {
  local dir=${1%/}
  if [ -f ${dir}/Dockerfile ]; then
    process_container $dir
    return
  fi
  for d in $(ls -d $dir/*/ 2>/dev/null); do
    if [[ $d != "./" && $d == */base* ]]; then
      process_dir $d
    fi
  done
  for d in $(ls -d $dir/*/ 2>/dev/null); do
    if [[ $d != "./" && $d != */base* ]]; then
      process_dir $d
    fi
  done
}

if [[ $path == 'list' ]] ; then
  op='list'
  path="."
fi

if [ -z $path ] || [ $path = 'all' ]; then
  path="."
fi

echo "INFO: starting build from $my_dir with relative path $path"
pushd $my_dir &>/dev/null

echo "INFO: prepare Contrail repo file in base image"
repo_template=$(sed 's/\(.*\){{ *\(.*\) *}}\(.*\)/\1$\2\3/g' $my_dir/../contrail.repo.template)
repo_content=$(eval "echo \"$repo_template\"")
update_contrail_repo='true'
if [[ -f base/contrail.repo && -f base/contrail.repo.md5 ]] ; then
  echo "INFO: base/contrail.repo and its checksum are exist, check them"
  new_repo_md5=$(echo "$repo_content" | md5sum | awk '{print($1)}')
  old_repo_md5=$(cat base/contrail.repo.md5 | awk '{print($1)}')
  if [[ "$old_repo_md5" == "$new_repo_md5" ]] ; then
    echo "INFO: content of contrail.repo is not changed"
    update_contrail_repo='false'
  fi
fi
if [[ "$update_contrail_repo" == 'true' ]] ; then
  echo "$repo_content" > base/contrail.repo
  md5sum base/contrail.repo > base/contrail.repo.md5
fi
process_dir $path

popd &>/dev/null

if [ $was_errors -ne 0 ]; then
  echo "ERROR: Failed to build some containers, see log files"
  exit 1
fi
