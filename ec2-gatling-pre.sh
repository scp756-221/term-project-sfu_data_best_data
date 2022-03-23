curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.21.2/2021-07-05/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
kubectl version --short --client
aws configure
aws sts get-caller-identity
aws eks --region us-west-2 update-kubeconfig --name aws756 --alias aws756
kubectl config set-context aws756 --namespace=project-services
kubectl get nodes
