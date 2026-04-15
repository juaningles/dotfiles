@echo kubectl config get-contexts -o name | xargs -I{} %*
@kubectl config get-contexts -o name | xargs -I{} %*
