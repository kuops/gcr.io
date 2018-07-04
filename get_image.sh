#!/bin/bash
REPOSITORY=gcr.io/google-containers
MY_REPO=kuops

git_init(){
    git config --global user.name "kuops"
    git config --global user.email opshsy@gmail.com
    git remote rm origin
    git remote add origin git@github.com:kuops/gcr.io.git
    git pull
    if git branch -a |grep 'origin/develop' &> /dev/null ;then
        git checkout develop
        git pull
        git branch --set-upstream-to=origin/develop develop
    else
        git checkout -b develop
        git pull
    fi
}

git_add(){
     GIT_STAT=$(git status -s|wc -l)
     if [ $GIT_STAT -ne 0 ];then
        git add -A
        git commit -m "sync at $(date +%F)"
        git push -u origin develop
     fi
}

install_sdk() {
    OS_VERSION=$(grep -Po '(?<=^ID=")\w+' /etc/os-release)
    OS_VERSION=${OS_VERSION:-ubuntu}
    if [[ $OS_VERSION =~ "centos" ]];then
        if ! [ -f /etc/yum.repos.d/google-cloud-sdk.repo ];then
            cat > /etc/yum.repos.d/google-cloud-sdk.repo <<EOF
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg

EOF
            yum -y install google-cloud-sdk
        else
            echo "gcloud is installed"
        fi
    elif [[ $OS_VERSION =~ "ubuntu" ]];then
        if ! [ -f /etc/apt/sources.list.d/google-cloud-sdk.list ];then
            export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
            echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
            curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
            sudo apt-get -y update && sudo apt-get -y install google-cloud-sdk
        else
             echo "gcloud is installed"
        fi
    fi    
}

initial_sdk(){
    local AUTH_COUNT=$(gcloud auth list --format="get(account)"|wc -l)
    if [ $AUTH_COUNT -eq 0 ];then
        gcloud auth activate-service-account --key-file=$HOME/gcloud.config.json
    else
        echo "gcloud service account is exsits"
    fi
}

repository_list() {
    if ! [ -f repository-file ];then
        gcloud container images list --repository=${REPOSITORY} --format="value(NAME)" > repository-file && \
        echo "get repository list done"
    else
        /bin/mv  -f repository-file old-repository-file
        gcloud container images list --repository=${REPOSITORY} --format="value(NAME)" > repository-file && \
        echo "get repository list done"
        DEL_REPO=($(diff  -B -c  old-repository-file repository-file |grep -Po '(?<=^\- ).+|xargs'))
        ADD_REPO=($(diff  -B -c  old-repository-file repository-file |grep -Po '(?<=^\+ ).+|xargs'))
        if [ ${#DEL_REPO} -ne 0 ];then
            for i in ${DEL_REPO[@]};do
                rm -rf ${i##*/}
            done
        fi
    fi
}

tag_push(){
    docker pull ${GCR_IMAGE_NAME}:${i}
    docker tag ${GCR_IMAGE_NAME}:${i} $MY_REPO/${IMAGE_NAME}:$i
    docker push $MY_REPO/${IMAGE_NAME}:$i
    echo "$IMAGE_TAG_SHA" > $IMAGE_NAME/$i
    sed -i  "1iadd ${MY_REPO}\/${IMAGE_NAME}\:${i}</br>"  CHANGE.md
}

clean_images(){
     IMAGES_COUNT=$(docker image ls|wc -l)
     if [ $IMAGES_COUNT -gt 1 ];then
         docker image prune -a -f
     fi
}
image_push() {
    if  ! [ -f CHANGE.md ];then
        echo  >> CHANGE.md
    fi
    PROGRESS_COUNT=0
    while read GCR_IMAGE_NAME;do
        IMAGE_INFO_JSON=$(gcloud container images list-tags $GCR_IMAGE_NAME  --filter="tags:*" --format=json)
        TAG_INFO_JSON=$(echo "$IMAGE_INFO_JSON"|jq '.[]|{ tag: .tags[] ,digest: .digest }')
        TAG_LIST=($(echo "$TAG_INFO_JSON"|jq -r .tag))
        IMAGE_NAME=${GCR_IMAGE_NAME##*/}
        for i in ${TAG_LIST[@]};do
            IMAGE_TAG_SHA=$(echo "${TAG_INFO_JSON}"|jq -r "select(.tag == \"$i\")|.digest")
            if [ -f $IMAGE_NAME/$i ];then
                echo "$IMAGE_TAG_SHA"  > /tmp/diff.txt
                if ! diff /tmp/diff.txt $IMAGE_NAME/$i &> /dev/null ;then
                     tag_push &
                     let PROGRESS_COUNT++
                fi
            else
                tag_push &
                let PROGRESS_COUNT++
            fi
            COUNT_WAIT=$[$PROGRESS_COUNT%20]
            if [ $COUNT_WAIT -eq 0 ];then
                wait
               clean_images
               git_add
            fi
        done
        echo "syncing image $MY_REPO/$IMAGE_NAME"
    done < repository-file
    if [ ${#ADD_TAG} -ne 0 ];then
        sed -i "1i-------------------------------at $(date +'%F %T') sync image repositorys-------------------------------"  CHANGE.md
        git_add
    fi
}

main(){
    git_init
    install_sdk
    initial_sdk
    repository_list
    image_push
}

main
