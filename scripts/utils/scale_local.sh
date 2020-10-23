#!/bin/bash
NAMESPACE=spinnaker
NAMESPACE_INGRESS=ingress-nginx

scale() {
    kubectl get deployments -n ${NAMESPACE} | awk '{ if (NR > 1) print $1}' | xargs -L1 kubectl scale deploy --replicas=$1 -n ${NAMESPACE}
    kubectl get statefulsets -n ${NAMESPACE} | awk '{ if (NR > 1) print $1}' | xargs -L1 kubectl scale sts --replicas=$1 -n ${NAMESPACE}
    kubectl get deployments -n ${NAMESPACE_INGRESS} | awk '{ if (NR > 1) print $1}' | xargs -L1 kubectl scale deploy --replicas=$1 -n ${NAMESPACE_INGRESS}
}

pause=false

for arg in "$@"
do
    case $arg in
        -p|--pause)
        pause=true
        shift 
        ;;
        -r|--resume|-s|--start)
        pause=false
        shift 
        ;;
        *)
        OTHER_ARGUMENTS+=("$1")
        shift # Remove generic argument from processing
        ;;
    esac
done

if [ $pause == true ]
then
    scale 0
else
    scale 1
fi