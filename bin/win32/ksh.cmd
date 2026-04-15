@echo off

@echo kubectl exec -it %* -- /bin/sh
kubectl exec -it %* -- /bin/sh
