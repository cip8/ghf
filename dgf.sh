#!/usr/bin/env bash

# Import .env file variables.
unamestr=$(uname)
SCRIPT_DIR=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
if [ "${unamestr}" = "Linux" ]; then
	export $(grep -v '^#' "${SCRIPT_DIR}"/.env | xargs -d '\n')
elif [ "${unamestr}" = "FreeBSD" ] || [ "${unamestr}" = "Darwin" ]; then
	export $(grep -v '^#' "${SCRIPT_DIR}"/.env | xargs -0)
fi

if [[ $# -lt 1 ]]; then
	echo "ERROR: URL required"
	exit
fi

# auth_token=""
# if [[ $# -ge 2 ]];
# then
# 	auth_token=$2
# fi

destination_path=""
if [[ $# -ge 2 ]]; then
	destination_path=$2
fi


url=$1
has_branch=$(echo ${url} | grep /tree/ > /dev/null; echo $?)
tokens=(${url//"/"/ })
tokens_len=$((${#tokens[@]} - 1))
owner=${tokens[2]}
repo=${tokens[3]}

if [[ $has_branch -eq 0 ]]; then
	branch=${tokens[5]}
	dir_path=${tokens[6]}
	dir_path_start_idx="7"
else
	dir_path=${tokens[4]}
	dir_path_start_idx="5"
fi

for ((i = ${dir_path_start_idx}; i <= ${tokens_len}; i++));
do
	dir_path="${dir_path}/${tokens[i]}"
done

# API Template "https://api.github.com/repos/${OWNER}/${REPO}/contents/${DIR_PATH}?ref=${BRANCH}"
contents_url="https://api.github.com/repos/${owner}/${repo}/contents"

if [[ "${dir_path}" != "" ]]; then
	contents_url="${contents_url}/${dir_path}"

	if [[ "${branch}" != "" ]]; then
		contents_url="${contents_url}?ref=${branch}"
	fi
fi

contents_file=$(mktemp)

accept_header="Accept: application/vnd.github.v3+json"
auth_header="Authorization: token ${GITHUB_KEY}"

if [ "${GITHUB_KEY}" = "" ]; then
	curl -s -H "${accept_header}" "${contents_url}" > ${contents_file}
else
	curl -s -H "${auth_header}" -H "${accept_header}" "${contents_url}" > ${contents_file}
fi

rate_exceeded=$(cat ${contents_file} | grep "API rate limit exceeded" > /dev/null; echo $?)

if [[ "${rate_exceeded}" -eq 0 ]]; then
	echo "ERROR : API Rate limit is exceeded."
	echo
	echo "If you have personal access token the limit will be increased. "
	echo "To use token, call me again like this:"
	echo
	echo "./download-github-folder <url> <token>"
	echo
	echo "For more info look at :"
	echo "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"

	exit 1
fi

file_names=$(cat ${contents_file} | grep "\"name\":")
file_names=${file_names//"\"name\":"/}
file_names=${file_names//"\""/}
file_names=${file_names//","/}
file_names=(${file_names})
paths=$(cat ${contents_file} | grep "\"path\":")
paths=${paths//"\"path\":"/}
paths=${paths//"\""/}
paths=${paths//","/}
paths=(${paths})
download_urls=$(cat ${contents_file} | grep "\"download_url\":")
download_urls=${download_urls//"\"download_url\":"/}
download_urls=${download_urls//"\""/}
download_urls=${download_urls//","/}
download_urls=(${download_urls})

n_files=${#file_names[@]}
runners=()

for ((i = 0; i < ${n_files}; i++));
do
	f_name=${file_names[i]}
	
	if [ "${destination_path}" = "" ]; then
		path=${repo}/${paths[i]}
	else
		path=${destination_path}/${file_names[i]}
	fi

	download_url=${download_urls[i]}

	if [[ "${#runners[@]}" -ge 10 ]];	then
		wait ${runners[@]}
		runners=()
	fi

	if [ "${download_url}" == "null" ];	then
		mkdir -p "${path}"
		echo ${path}
		$0 "${url}/${f_name}" "${path}"

		if [[ "$?" -ne 0 ]]; then
			echo "Error"
			exit $?
		fi

		continue;

	else
		mkdir -p $(dirname "${path}")
		echo ${path}
		curl -s "${download_url}" > "${path}" &
		runners+=($!)
	fi
done
