## AWS Platform Overview

This stack demonstrates how to provision an EKS cluster, deploy Argo CD via Terraform/Helm, and wire it up to external services such as AWS Secrets Manager and ElastiCache Redis. The goal is to showcase a production-friendly setup where Argo CD runs behind the AWS Load Balancer Controller with an external Redis backend and all sensitive values managed outside the cluster.

## Prereqs
- **Route53 domain**:
  - Either **register a new domain in Route53** (`Route 53 → Registered domains → Register domain`).
  - Or use an **existing domain** and create / verify a **public hosted zone** in Route53 for it (`Route 53 → Hosted zones → Create hosted zone`).
  - Make sure the **hosted zone and this Terraform stack are in the same AWS account** so Terraform can manage Route53 records.
  - If the domain is registered elsewhere (GoDaddy, Namecheap, etc.), update the **NS records at your registrar** to point at the Route53 hosted zone’s name servers.

Create kubeconfig so we can connect to EKS with kubectl
```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>

aws eks update-kubeconfig \
  --name test-eks-cluster \
  --region us-east-1 \
  --role-arn arn:aws:iam::<aws-account-id>:role/<your-assumed-iam-role>
```


Grab ingress url of argocd once its running:
```bash
kubectl get ingress -n argocd argo-cd-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

You can visit the URL and login by grabbing the secret value from AWS Secrets Manager

## Debug ArgoCD + ExternalRedis

- Debugging external Redis for Argo CD:
  - `kubectl -n argocd exec argo-cd-argocd-application-controller-0 -c application-controller -- env | grep REDIS` to confirm the pod is wired to the right ElastiCache host, username, and password.
  

  - Check and make sure the `argocd-application-controller` pod doesn't have errors.`kubectl -n argocd logs argo-cd-argocd-application-controller-0 -c application-controller | grep -i redis` if there isn't any `i/o timeout` or `server timeout` messages, the controller is successfully talking to Redis.

  - Launch a one-off pod to test the network path: `kubectl run redis-debug -n argocd --restart=Never --rm -it --image=redis:7 --command -- sh` and inside run `redis-cli -h <elasticache-endpoint> -p 6379 ping` (add `--tls` and `-a $REDIS_PASSWORD` if TLS/auth is enabled). A `PONG` confirms the cluster can reach ElastiCache.
  - If TLS is required, set the Argo CD Helm values to use tls for redis.

  ```json
    controller = {
        extraArgs = [
        "--redis-use-tls",
        ]
    }

    repoServer = {
        extraArgs = [
        "--redis-use-tls",
        ]
    }


    server = {
        extraArgs = [
        "--redis-use-tls",
        ]
    }
	...