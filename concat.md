# Repository Structure

- **.github/**
  - **workflows/**
    - dev.yml
    - prd.yml
- **deploy-yml/**
  - cert-manager-values.yaml
  - digital_ocean_steps.md
  - letsencrypt-prod-1.6+.yaml
  - not-needed-created-with-helm-rabbitmq-cluster-operator.yml
  - not-needed-created-with-helm-rabbitmq-cluster.yaml
  - not-needed-created-with-terraform-configmap.yaml
  - not-needed-created-with-terraform-ingress.yaml
  - not-needed-created-with-terraform-secret.yaml
- **env/**
  - **dev/**
    - datadog-values.yaml
  - **prd/**
    - datadog-values.yaml

---

## File: `.github/workflows/dev.yml`
- **File Size:** 5687 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** fix

```
name: "[dev] Deploy DO Laliga Infra"

defaults:
  run:
    shell: bash

env:
  AWS_REGION: us-east-1
  AWS_MFA_ENABLED: false
  AWS_PROFILE: infra-dev
  ENV: dev
  NAMESPACE: fanclash-dev
  SSH_PUBLIC_KEY: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsCXa8jvBRjf9Pq7WGUIe2Ct8tSs0YijT5OxTL9hsCK pc@Muharrems-MacBook-Pro.local"

on:
  push:
    branches:
      - main
    paths-ignore:
      - '**.md'
      - '**.svg'
      - '**.png'
      - '.gitignore'

jobs:
  changes:
    name: code changes
    runs-on: ubuntu-latest
    # Set job outputs to values from filter step
    timeout-minutes: 2
    outputs:
      infra: ${{ steps.filter.outputs.infra }}
    steps:
    - name: Setup Node.js 20
      uses: actions/setup-node@v3
      with:
        node-version: '20'
    - name: Checkout Code
      uses: actions/checkout@v3
    - name: Filter Paths
      uses: dorny/paths-filter@v3
      id: filter
      with:
        filters: |
          infra:
            - 'env/dev/**'
  infra:
    # needs: 
    #   - changes
    # if: ${{ needs.changes.outputs.infra == 'true' }}
    name: infra
    timeout-minutes: 10
    runs-on: ubuntu-latest
    permissions:
      contents: 'read'
      id-token: 'write'
    steps:
      - name: Setup Node.js 20
        uses: actions/setup-node@v3
        with:
          node-version: '20'
      # - name: configure aws credentials
      #   uses: aws-actions/configure-aws-credentials@v1
      #   with:
      #     role-to-assume: arn:aws:iam::736790963086:role/github-actions-role
      #     role-duration-seconds: 1200 # the ttl of the session, in seconds.
      #     aws-region: us-east-1 # use your region here.
      - name: create profile 
        run: |
          mkdir -p ~/.aws && echo -e "[${{ env.AWS_PROFILE }}]\naws_access_key_id = DO00Z4GUZ8HWDVWWXVWZ\naws_secret_access_key = rrht8SySmhn2UDqEl0THgKVZeyhKj6PfXiWkTP94104\nregion = nyc3" >> ~/.aws/credentials
          cat ~/.aws/credentials
          echo "[profile infra-prd]" >> ~/.aws/config
          echo "region = us-east-1" >> ~/.aws/config

      - name: checkoutout
        uses: actions/checkout@v3
        with:
          submodules: true

      - name: Install doctl 
        uses: digitalocean/action-doctl@v2
        with:
            token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

      - name: Log in to DO Container Registry 
        run: doctl registry login --expiry-seconds 600

      - name: Configure Kubectl for DOKS
        run: doctl kubernetes cluster kubeconfig save dev-fanclash

      - name: setup terraform
        uses: hashicorp/setup-terraform@v2

      - name: Import GPG Key and Decrypt Terraform Secrets File
        working-directory: ./env/${{ env.ENV }}
        run: |
          # Import the GPG private key from the GitHub secret
          echo "${{ secrets.GPG_PRIVATE_KEY_BASE64 }}" | base64 -d | gpg --batch --yes --import
        
          # Ensure gpg-agent is running and configured for loopback mode
          echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf
          echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf
          gpgconf --reload gpg-agent

          # Decrypt the Terraform secrets file with the passphrase provided inline
          gpg --batch --yes --pinentry-mode loopback --passphrase "gameon-laliga" --decrypt --output cluster-secrets.tf cluster-secrets.tf.gpg

      - name: terraform commands
        working-directory: ./env/${{ env.ENV }}
        id: fmt
        run: |
          terraform fmt -check
        continue-on-error: true

      - name: terraform init
        working-directory: ./env/${{ env.ENV }}
        id: init
        run: |
          terraform init

      - name: terraform validate
        working-directory: ./env/${{ env.ENV }}
        id: validate
        run: |
          terraform validate -no-color

      - name: terraform plan
        working-directory: ./env/${{ env.ENV }}
        id: plan
        run: |
          terraform plan -no-color \
            -var="do_token=${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}" \
            -var="do_spaces_access_id=${{ secrets.DO_SPACES_ACCESS_ID }}" \
            -var="do_spaces_secret_key=${{ secrets.DO_SPACES_SECRET_KEY }}" \
            -input=false

      - name: terraform plan status
        working-directory: ./env/${{ env.ENV }}
        if: steps.plan.outcome == 'failure'
        run: exit 1
      # - name: terraform import existing resources
      #   working-directory: ./env/${{ env.ENV }}
      #   env:
      #     DIGITALOCEAN_ACCESS_TOKEN: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }} # Setting the token as an environment variable

      #   run: |
      #     # terraform import -var do_token="${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}" kubernetes_secret_v1.db-creds fanclash-dev/db-creds

      - name: terraform apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        working-directory: ./env/${{ env.ENV }}
        run: |
          terraform apply -auto-approve \
            -var="do_token=${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}" \
            -var="do_spaces_access_id=${{ secrets.DO_SPACES_ACCESS_ID }}" \
            -var="do_spaces_secret_key=${{ secrets.DO_SPACES_SECRET_KEY }}" \
            -input=false

      - name: Slack Notification
        if: always()
        uses: rtCamp/action-slack-notify@v2
        env:
          SLACK_CHANNEL: staging-deployments
          SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK_STAGING_URL }}
          SLACK_ICON_EMOJI: ':gameon:'
          SLACK_USERNAME: GitHubAction
          SLACK_COLOR: ${{ job.status }}
          SLACK_TITLE: 'Dev Fanclash infra deployment. Commit message:'
          SLACK_FOOTER: Powered By GameOn DevOps team
```

## File: `.github/workflows/prd.yml`
- **File Size:** 5319 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** Update prd.yml

```
name: "[prd] Deploy DO Laliga Infra"

defaults:
  run:
    shell: bash

env:
  AWS_REGION: us-east-1
  AWS_MFA_ENABLED: false
  AWS_PROFILE: infra-prd
  ENV: prd
  NAMESPACE: prd-fanclash
  SSH_PUBLIC_KEY: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsCXa8jvBRjf9Pq7WGUIe2Ct8tSs0YijT5OxTL9hsCK pc@Muharrems-MacBook-Pro.local"

on:
  push:
    branches:
      - prd
    paths-ignore:
      - '**.md'
      - '**.svg'
      - '**.png'
      - '.gitignore'

jobs:
  changes:
    name: code changes
    runs-on: ubuntu-latest
    # Set job outputs to values from filter step
    timeout-minutes: 2
    outputs:
      infra: ${{ steps.filter.outputs.infra }}
    steps:
    - name: Setup Node.js 20
      uses: actions/setup-node@v3
      with:
        node-version: '20'
    - name: Checkout Code
      uses: actions/checkout@v3
    - name: Filter Paths
      uses: dorny/paths-filter@v3
      id: filter
      with:
        filters: |
          infra:
            - 'env/prd/**'
  infra:
    needs: 
      - changes
    if: ${{ needs.changes.outputs.infra == 'true' }}
    name: infra
    timeout-minutes: 10
    runs-on: ubuntu-latest
    permissions:
      contents: 'read'
      id-token: 'write'
    steps:
      - name: Setup Node.js 20
        uses: actions/setup-node@v3
        with:
          node-version: '20'
      - name: configure aws credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          role-to-assume: arn:aws:iam::826737140156:role/github-actions-role
          role-duration-seconds: 1200 # the ttl of the session, in seconds.
          aws-region: us-east-1 # use your region here.
      - name: create profile 
        run: |
          mkdir -p ~/.aws && echo -e "[${{ env.AWS_PROFILE }}]\naws_access_key_id = $AWS_ACCESS_KEY_ID\naws_secret_access_key = $AWS_SECRET_ACCESS_KEY\nregion = $AWS_DEFAULT_REGION" >> ~/.aws/credentials
          cat ~/.aws/credentials
          Optionally set the region in the config file too
          echo "[profile infra-prd]" >> ~/.aws/config
          echo "region = us-east-1" >> ~/.aws/config

      - name: checkoutout
        uses: actions/checkout@v3
        with:
          submodules: true

      - name: Install doctl 
        uses: digitalocean/action-doctl@v2
        with:
            token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

      - name: Log in to DO Container Registry 
        run: doctl registry login --expiry-seconds 600

      - name: Configure Kubectl for DOKS
        run: doctl kubernetes cluster kubeconfig save dev-fanclash

      - name: setup terraform
        uses: hashicorp/setup-terraform@v2

      - name: Import GPG Key and Decrypt Terraform Secrets File
        working-directory: ./env/${{ env.ENV }}
        run: |
          Import the GPG private key from the GitHub secret
          echo "${{ secrets.GPG_PRIVATE_KEY_BASE64 }}" | base64 -d | gpg --batch --yes --import
        
          Ensure gpg-agent is running and configured for loopback mode
          echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf
          echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf
          gpgconf --reload gpg-agent

          Decrypt the Terraform secrets file with the passphrase provided inline
          gpg --batch --yes --pinentry-mode loopback --passphrase "prd-gpg-gameon" --decrypt --output cluster-secrets.tf cluster-secrets.tf.gpg

      - name: terraform commands
        working-directory: ./env/${{ env.ENV }}
        id: fmt
        run: |
          terraform fmt -check
        continue-on-error: true

      - name: terraform init
        working-directory: ./env/${{ env.ENV }}
        id: init
        run: |
          terraform init

      - name: terraform validate
        working-directory: ./env/${{ env.ENV }}
        id: validate
        run: |
          terraform validate -no-color

      - name: terraform plan
        working-directory: ./env/${{ env.ENV }}
        id: plan
        run: |
          terraform plan -no-color \
            -var="do_token=${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}" \
            -input=false
            # -var="do_spaces_access_id=${{ secrets.DO_SPACES_ACCESS_ID }}" \
            # -var="do_spaces_secret_key=${{ secrets.DO_SPACES_SECRET_KEY }}" 
      - name: terraform plan status
        working-directory: ./env/${{ env.ENV }}
        if: steps.plan.outcome == 'failure'
        run: exit 1

      - name: terraform apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        working-directory: ./env/${{ env.ENV }}
        run: |
          terraform apply -auto-approve \
            -var="do_token=${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}" \
            -input=false
           # -var="do_spaces_access_id=${{ secrets.DO_SPACES_ACCESS_ID }}" \
           # -var="do_spaces_secret_key=${{ secrets.DO_SPACES_SECRET_KEY }}" \
      - name: Slack Notification
        if: always()
        uses: rtCamp/action-slack-notify@v2
        env:
          SLACK_CHANNEL: production-deployments
          SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK_NEW_PRD_URL }}
          SLACK_ICON_EMOJI: ':gameon:'
          SLACK_USERNAME: GitHubAction
          SLACK_COLOR: ${{ job.status }}
          SLACK_TITLE: 'Prd Fanclash infra deployment. Commit message:'
          SLACK_FOOTER: Powered By GameOn DevOps team

```

## File: `deploy-yml/cert-manager-values.yaml`
- **File Size:** 92 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** ingress created with terraform and ssl added

```
ingressShim.defaultIssuerName: letsencrypt-prod
ingressShim.defaultIssuerKind: ClusterIssuer
```

## File: `deploy-yml/digital_ocean_steps.md`
- **File Size:** 1503 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** infra deployment automation

```
Install locally `helm` and `doctl` and auth (https://docs.digitalocean.com/reference/doctl/how-to/install/)

# digital ocean ui
create kubernetes cluster 
create registry, attach it to the kubernetes cluster
create postgresql db, add k8s cluster as trusted source
connect to postgresql, give permissions to user

# rabbitmq
install rabbitmq kubernetes operator (https://www.rabbitmq.com/kubernetes/operator/install-operator.html)
```
kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
```

create rabbimtq cluster (https://www.rabbitmq.com/kubernetes/operator/using-operator.html)
```
kubectl apply -f ./k8s/030-rabbitmq-cluster.yaml
```

connect to management panel using port-forward - 15672 then http://localhost:15672/   # you need to retrieve the password and username with this command
# Retrieve the password
kubectl get secret rabbitmq-cluster -n rabbitmq-system -o jsonpath='{.data.rabbitmq-password}' | base64 --decode && echo

# Retrieve the username
"user"

kubectl port-forward service/rabbitmq-cluster 15672:15672 -n rabbitmq-system
create vhost `ufl` in the management panel. 

# create configs, secrets

```
kubectl apply -f ./k8s/010-configmap.yaml
kubectl apply -f ./k8s/020-secret.yaml
```

# launch services in following order
- rabbitmq_publisher

# install ingress controller
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/do/deploy.yaml
```

```

## File: `deploy-yml/letsencrypt-prod-1.6+.yaml`
- **File Size:** 524 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** ingress created with terraform and ssl added

```
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # The ACME production server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: muharrem@gameon.app
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-prod
    # Enable the HTTP-01 challenge provider

    solvers:
    - selector: {}
      http01:
        ingress:
          class: nginx
```

## File: `deploy-yml/not-needed-created-with-helm-rabbitmq-cluster-operator.yml`
- **File Size:** 316855 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** create ingress rules with terraform

```
apiVersion: v1
kind: Namespace
metadata:
  labels:
    app.kubernetes.io/component: rabbitmq-operator
    app.kubernetes.io/name: rabbitmq-system
    app.kubernetes.io/part-of: rabbitmq
  name: rabbitmq-system
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.13.0
  labels:
    app.kubernetes.io/component: rabbitmq-operator
    app.kubernetes.io/name: rabbitmq-cluster-operator
    app.kubernetes.io/part-of: rabbitmq
    servicebinding.io/provisioned-service: "true"
  name: rabbitmqclusters.rabbitmq.com
spec:
  group: rabbitmq.com
  names:
    categories:
    - all
    - rabbitmq
    kind: RabbitmqCluster
    listKind: RabbitmqClusterList
    plural: rabbitmqclusters
    shortNames:
    - rmq
    singular: rabbitmqcluster
  scope: Namespaced
  versions:
  - additionalPrinterColumns:
    - jsonPath: .status.conditions[?(@.type == 'AllReplicasReady')].status
      name: AllReplicasReady
      type: string
    - jsonPath: .status.conditions[?(@.type == 'ReconcileSuccess')].status
      name: ReconcileSuccess
      type: string
    - jsonPath: .metadata.creationTimestamp
      name: Age
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: RabbitmqCluster is the Schema for the RabbitmqCluster API. Each
          instance of this object corresponds to a single RabbitMQ cluster.
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation
              of an object. Servers should convert recognized schemas to the latest
              internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this
              object represents. Servers may infer this from the endpoint the client
              submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          metadata:
            type: object
          spec:
            description: Spec is the desired state of the RabbitmqCluster Custom Resource.
            properties:
              affinity:
                description: Affinity scheduling rules to be applied on created Pods.
                properties:
                  nodeAffinity:
                    description: Describes node affinity scheduling rules for the
                      pod.
                    properties:
                      preferredDuringSchedulingIgnoredDuringExecution:
                        description: The scheduler will prefer to schedule pods to
                          nodes that satisfy the affinity expressions specified by
                          this field, but it may choose a node that violates one or
                          more of the expressions. The node that is most preferred
                          is the one with the greatest sum of weights, i.e. for each
                          node that meets all of the scheduling requirements (resource
                          request, requiredDuringScheduling affinity expressions,
                          etc.), compute a sum by iterating through the elements of
                          this field and adding "weight" to the sum if the node matches
                          the corresponding matchExpressions; the node(s) with the
                          highest sum are the most preferred.
                        items:
                          description: An empty preferred scheduling term matches
                            all objects with implicit weight 0 (i.e. it's a no-op).
                            A null preferred scheduling term matches no objects (i.e.
                            is also a no-op).
                          properties:
                            preference:
                              description: A node selector term, associated with the
                                corresponding weight.
                              properties:
                                matchExpressions:
                                  description: A list of node selector requirements
                                    by node's labels.
                                  items:
                                    description: A node selector requirement is a
                                      selector that contains values, a key, and an
                                      operator that relates the key and values.
                                    properties:
                                      key:
                                        description: The label key that the selector
                                          applies to.
                                        type: string
                                      operator:
                                        description: Represents a key's relationship
                                          to a set of values. Valid operators are
                                          In, NotIn, Exists, DoesNotExist. Gt, and
                                          Lt.
                                        type: string
                                      values:
                                        description: An array of string values. If
                                          the operator is In or NotIn, the values
                                          array must be non-empty. If the operator
                                          is Exists or DoesNotExist, the values array
                                          must be empty. If the operator is Gt or
                                          Lt, the values array must have a single
                                          element, which will be interpreted as an
                                          integer. This array is replaced during a
                                          strategic merge patch.
                                        items:
                                          type: string
                                        type: array
                                    required:
                                    - key
                                    - operator
                                    type: object
                                  type: array
                                matchFields:
                                  description: A list of node selector requirements
                                    by node's fields.
                                  items:
                                    description: A node selector requirement is a
                                      selector that contains values, a key, and an
                                      operator that relates the key and values.
                                    properties:
                                      key:
                                        description: The label key that the selector
                                          applies to.
                                        type: string
                                      operator:
                                        description: Represents a key's relationship
                                          to a set of values. Valid operators are
                                          In, NotIn, Exists, DoesNotExist. Gt, and
                                          Lt.
                                        type: string
                                      values:
                                        description: An array of string values. If
                                          the operator is In or NotIn, the values
                                          array must be non-empty. If the operator
                                          is Exists or DoesNotExist, the values array
                                          must be empty. If the operator is Gt or
                                          Lt, the values array must have a single
                                          element, which will be interpreted as an
                                          integer. This array is replaced during a
                                          strategic merge patch.
                                        items:
                                          type: string
                                        type: array
                                    required:
                                    - key
                                    - operator
                                    type: object
                                  type: array
                              type: object
                              x-kubernetes-map-type: atomic
                            weight:
                              description: Weight associated with matching the corresponding
                                nodeSelectorTerm, in the range 1-100.
                              format: int32
                              type: integer
                          required:
                          - preference
                          - weight
                          type: object
                        type: array
                      requiredDuringSchedulingIgnoredDuringExecution:
                        description: If the affinity requirements specified by this
                          field are not met at scheduling time, the pod will not be
                          scheduled onto the node. If the affinity requirements specified
                          by this field cease to be met at some point during pod execution
                          (e.g. due to an update), the system may or may not try to
                          eventually evict the pod from its node.
                        properties:
                          nodeSelectorTerms:
                            description: Required. A list of node selector terms.
                              The terms are ORed.
                            items:
                              description: A null or empty node selector term matches
                                no objects. The requirements of them are ANDed. The
                                TopologySelectorTerm type implements a subset of the
                                NodeSelectorTerm.
                              properties:
                                matchExpressions:
                                  description: A list of node selector requirements
                                    by node's labels.
                                  items:
                                    description: A node selector requirement is a
                                      selector that contains values, a key, and an
                                      operator that relates the key and values.
                                    properties:
                                      key:
                                        description: The label key that the selector
                                          applies to.
                                        type: string
                                      operator:
                                        description: Represents a key's relationship
                                          to a set of values. Valid operators are
                                          In, NotIn, Exists, DoesNotExist. Gt, and
                                          Lt.
                                        type: string
                                      values:
                                        description: An array of string values. If
                                          the operator is In or NotIn, the values
                                          array must be non-empty. If the operator
                                          is Exists or DoesNotExist, the values array
                                          must be empty. If the operator is Gt or
                                          Lt, the values array must have a single
                                          element, which will be interpreted as an
                                          integer. This array is replaced during a
                                          strategic merge patch.
                                        items:
                                          type: string
                                        type: array
                                    required:
                                    - key
                                    - operator
                                    type: object
                                  type: array
                                matchFields:
                                  description: A list of node selector requirements
                                    by node's fields.
                                  items:
                                    description: A node selector requirement is a
                                      selector that contains values, a key, and an
                                      operator that relates the key and values.
                                    properties:
                                      key:
                                        description: The label key that the selector
                                          applies to.
                                        type: string
                                      operator:
                                        description: Represents a key's relationship
                                          to a set of values. Valid operators are
                                          In, NotIn, Exists, DoesNotExist. Gt, and
                                          Lt.
                                        type: string
                                      values:
                                        description: An array of string values. If
                                          the operator is In or NotIn, the values
                                          array must be non-empty. If the operator
                                          is Exists or DoesNotExist, the values array
                                          must be empty. If the operator is Gt or
                                          Lt, the values array must have a single
                                          element, which will be interpreted as an
                                          integer. This array is replaced during a
                                          strategic merge patch.
                                        items:
                                          type: string
                                        type: array
                                    required:
                                    - key
                                    - operator
                                    type: object
                                  type: array
                              type: object
                              x-kubernetes-map-type: atomic
                            type: array
                        required:
                        - nodeSelectorTerms
                        type: object
                        x-kubernetes-map-type: atomic
                    type: object
                  podAffinity:
                    description: Describes pod affinity scheduling rules (e.g. co-locate
                      this pod in the same node, zone, etc. as some other pod(s)).
                    properties:
                      preferredDuringSchedulingIgnoredDuringExecution:
                        description: The scheduler will prefer to schedule pods to
                          nodes that satisfy the affinity expressions specified by
                          this field, but it may choose a node that violates one or
                          more of the expressions. The node that is most preferred
                          is the one with the greatest sum of weights, i.e. for each
                          node that meets all of the scheduling requirements (resource
                          request, requiredDuringScheduling affinity expressions,
                          etc.), compute a sum by iterating through the elements of
                          this field and adding "weight" to the sum if the node has
                          pods which matches the corresponding podAffinityTerm; the
                          node(s) with the highest sum are the most preferred.
                        items:
                          description: The weights of all of the matched WeightedPodAffinityTerm
                            fields are added per-node to find the most preferred node(s)
                          properties:
                            podAffinityTerm:
                              description: Required. A pod affinity term, associated
                                with the corresponding weight.
                              properties:
                                labelSelector:
                                  description: A label query over a set of resources,
                                    in this case pods. If it's null, this PodAffinityTerm
                                    matches with no Pods.
                                  properties:
                                    matchExpressions:
                                      description: matchExpressions is a list of label
                                        selector requirements. The requirements are
                                        ANDed.
                                      items:
                                        description: A label selector requirement
                                          is a selector that contains values, a key,
                                          and an operator that relates the key and
                                          values.
                                        properties:
                                          key:
                                            description: key is the label key that
                                              the selector applies to.
                                            type: string
                                          operator:
                                            description: operator represents a key's
                                              relationship to a set of values. Valid
                                              operators are In, NotIn, Exists and
                                              DoesNotExist.
                                            type: string
                                          values:
                                            description: values is an array of string
                                              values. If the operator is In or NotIn,
                                              the values array must be non-empty.
                                              If the operator is Exists or DoesNotExist,
                                              the values array must be empty. This
                                              array is replaced during a strategic
                                              merge patch.
                                            items:
                                              type: string
                                            type: array
                                        required:
                                        - key
                                        - operator
                                        type: object
                                      type: array
                                    matchLabels:
                                      additionalProperties:
                                        type: string
                                      description: matchLabels is a map of {key,value}
                                        pairs. A single {key,value} in the matchLabels
                                        map is equivalent to an element of matchExpressions,
                                        whose key field is "key", the operator is
                                        "In", and the values array contains only "value".
                                        The requirements are ANDed.
                                      type: object
                                  type: object
                                  x-kubernetes-map-type: atomic
                                matchLabelKeys:
                                  description: MatchLabelKeys is a set of pod label
                                    keys to select which pods will be taken into consideration.
                                    The keys are used to lookup values from the incoming
                                    pod labels, those key-value labels are merged
                                    with `LabelSelector` as `key in (value)` to select
                                    the group of existing pods which pods will be
                                    taken into consideration for the incoming pod's
                                    pod (anti) affinity. Keys that don't exist in
                                    the incoming pod labels will be ignored. The default
                                    value is empty. The same key is forbidden to exist
                                    in both MatchLabelKeys and LabelSelector. Also,
                                    MatchLabelKeys cannot be set when LabelSelector
                                    isn't set. This is an alpha field and requires
                                    enabling MatchLabelKeysInPodAffinity feature gate.
                                  items:
                                    type: string
                                  type: array
                                  x-kubernetes-list-type: atomic
                                mismatchLabelKeys:
                                  description: MismatchLabelKeys is a set of pod label
                                    keys to select which pods will be taken into consideration.
                                    The keys are used to lookup values from the incoming
                                    pod labels, those key-value labels are merged
                                    with `LabelSelector` as `key notin (value)` to
                                    select the group of existing pods which pods will
                                    be taken into consideration for the incoming pod's
                                    pod (anti) affinity. Keys that don't exist in
                                    the incoming pod labels will be ignored. The default
                                    value is empty. The same key is forbidden to exist
                                    in both MismatchLabelKeys and LabelSelector. Also,
                                    MismatchLabelKeys cannot be set when LabelSelector
                                    isn't set. This is an alpha field and requires
                                    enabling MatchLabelKeysInPodAffinity feature gate.
                                  items:
                                    type: string
                                  type: array
                                  x-kubernetes-list-type: atomic
                                namespaceSelector:
                                  description: A label query over the set of namespaces
                                    that the term applies to. The term is applied
                                    to the union of the namespaces selected by this
                                    field and the ones listed in the namespaces field.
                                    null selector and null or empty namespaces list
                                    means "this pod's namespace". An empty selector
                                    ({}) matches all namespaces.
                                  properties:
                                    matchExpressions:
                                      description: matchExpressions is a list of label
                                        selector requirements. The requirements are
                                        ANDed.
                                      items:
                                        description: A label selector requirement
                                          is a selector that contains values, a key,
                                          and an operator that relates the key and
                                          values.
                                        properties:
                                          key:
                                            description: key is the label key that
                                              the selector applies to.
                                            type: string
                                          operator:
                                            description: operator represents a key's
                                              relationship to a set of values. Valid
                                              operators are In, NotIn, Exists and
                                              DoesNotExist.
                                            type: string
                                          values:
                                            description: values is an array of string
                                              values. If the operator is In or NotIn,
                                              the values array must be non-empty.
                                              If the operator is Exists or DoesNotExist,
                                              the values array must be empty. This
                                              array is replaced during a strategic
                                              merge patch.
                                            items:
                                              type: string
                                            type: array
                                        required:
                                        - key
                                        - operator
                                        type: object
                                      type: array
                                    matchLabels:
                                      additionalProperties:
                                        type: string
                                      description: matchLabels is a map of {key,value}
                                        pairs. A single {key,value} in the matchLabels
                                        map is equivalent to an element of matchExpressions,
                                        whose key field is "key", the operator is
                                        "In", and the values array contains only "value".
                                        The requirements are ANDed.
                                      type: object
                                  type: object
                                  x-kubernetes-map-type: atomic
                                namespaces:
                                  description: namespaces specifies a static list
                                    of namespace names that the term applies to. The
                                    term is applied to the union of the namespaces
                                    listed in this field and the ones selected by
                                    namespaceSelector. null or empty namespaces list
                                    and null namespaceSelector means "this pod's namespace".
                                  items:
                                    type: string
                                  type: array
                                topologyKey:
                                  description: This pod should be co-located (affinity)
                                    or not co-located (anti-affinity) with the pods
                                    matching the labelSelector in the specified namespaces,
                                    where co-located is defined as running on a node
                                    whose value of the label with key topologyKey
                                    matches that of any node on which any of the selected
                                    pods is running. Empty topologyKey is not allowed.
                                  type: string
                              required:
                              - topologyKey
                              type: object
                            weight:
                              description: weight associated with matching the corresponding
                                podAffinityTerm, in the range 1-100.
                              format: int32
                              type: integer
                          required:
                          - podAffinityTerm
                          - weight
                          type: object
                        type: array
                      requiredDuringSchedulingIgnoredDuringExecution:
                        description: If the affinity requirements specified by this
                          field are not met at scheduling time, the pod will not be
                          scheduled onto the node. If the affinity requirements specified
                          by this field cease to be met at some point during pod execution
                          (e.g. due to a pod label update), the system may or may
                          not try to eventually evict the pod from its node. When
                          there are multiple elements, the lists of nodes corresponding
                          to each podAffinityTerm are intersected, i.e. all terms
                          must be satisfied.
                        items:
                          description: Defines a set of pods (namely those matching
                            the labelSelector relative to the given namespace(s))
                            that this pod should be co-located (affinity) or not co-located
                            (anti-affinity) with, where co-located is defined as running
                            on a node whose value of the label with key <topologyKey>
                            matches that of any node on which a pod of the set of
                            pods is running
                          properties:
                            labelSelector:
                              description: A label query over a set of resources,
                                in this case pods. If it's null, this PodAffinityTerm
                                matches with no Pods.
                              properties:
                                matchExpressions:
                                  description: matchExpressions is a list of label
                                    selector requirements. The requirements are ANDed.
                                  items:
                                    description: A label selector requirement is a
                                      selector that contains values, a key, and an
                                      operator that relates the key and values.
                                    properties:
                                      key:
                                        description: key is the label key that the
                                          selector applies to.
                                        type: string
                                      operator:
                                        description: operator represents a key's relationship
                                          to a set of values. Valid operators are
                                          In, NotIn, Exists and DoesNotExist.
                                        type: string
                                      values:
                                        description: values is an array of string
                                          values. If the operator is In or NotIn,
                                          the values array must be non-empty. If the
                                          operator is Exists or DoesNotExist, the
                                          values array must be empty. This array is
                                          replaced during a strategic merge patch.
                                        items:
                                          type: string
                                        type: array
                                    required:
                                    - key
                                    - operator
                                    type: object
                                  type: array
                                matchLabels:
                                  additionalProperties:
                                    type: string
                                  description: matchLabels is a map of {key,value}
                                    pairs. A single {key,value} in the matchLabels
                                    map is equivalent to an element of matchExpressions,
                                    whose key field is "key", the operator is "In",
                                    and the values array contains only "value". The
                                    requirements are ANDed.
                                  type: object
                              type: object
                              x-kubernetes-map-type: atomic
                            matchLabelKeys:
                              description: MatchLabelKeys is a set of pod label keys
                                to select which pods will be taken into consideration.
                                The keys are used to lookup values from the incoming
                                pod labels, those key-value labels are merged with
                                `LabelSelector` as `key in (value)` to select the
                                group of existing pods which pods will be taken into
                                consideration for the incoming pod's pod (anti) affinity.
                                Keys that don't exist in the incoming pod labels will
                                be ignored. The default value is empty. The same key
                                is forbidden to exist in both MatchLabelKeys and LabelSelector.
                                Also, MatchLabelKeys cannot be set when LabelSelector
                                isn't set. This is an alpha field and requires enabling
                                MatchLabelKeysInPodAffinity feature gate.
                              items:
                                type: string
                              type: array
                              x-kubernetes-list-type: atomic
                            mismatchLabelKeys:
                              description: MismatchLabelKeys is a set of pod label
                                keys to select which pods will be taken into consideration.
                                The keys are used to lookup values from the incoming
                                pod labels, those key-value labels are merged with
                                `LabelSelector` as `key notin (value)` to select the
                                group of existing pods which pods will be taken into
                                consideration for the incoming pod's pod (anti) affinity.
                                Keys that don't exist in the incoming pod labels will
                                be ignored. The default value is empty. The same key
                                is forbidden to exist in both MismatchLabelKeys and
                                LabelSelector. Also, MismatchLabelKeys cannot be set
                                when LabelSelector isn't set. This is an alpha field
                                and requires enabling MatchLabelKeysInPodAffinity
                                feature gate.
                              items:
                                type: string
                              type: array
                              x-kubernetes-list-type: atomic
                            namespaceSelector:
                              description: A label query over the set of namespaces
                                that the term applies to. The term is applied to the
                                union of the namespaces selected by this field and
                                the ones listed in the namespaces field. null selector
                                and null or empty namespaces list means "this pod's
                                namespace". An empty selector ({}) matches all namespaces.
                              properties:
                                matchExpressions:
                                  description: matchExpressions is a list of label
                                    selector requirements. The requirements are ANDed.
                                  items:
                                    description: A label selector requirement is a
                                      selector that contains values, a key, and an
                                      operator that relates the key and values.
                                    properties:
                                      key:
                                        description: key is the label key that the
                                          selector applies to.
                                        type: string
                                      operator:
                                        description: operator represents a key's relationship
                                          to a set of values. Valid operators are
                                          In, NotIn, Exists and DoesNotExist.
                                        type: string
                                      values:
                                        description: values is an array of string
                                          values. If the operator is In or NotIn,
                                          the values array must be non-empty. If the
                                          operator is Exists or DoesNotExist, the
                                          values array must be empty. This array is
                                          replaced during a strategic merge patch.
                                        items:
                                          type: string
                                        type: array
                                    required:
                                    - key
                                    - operator
                                    type: object
                                  type: array
                                matchLabels:
                                  additionalProperties:
                                    type: string
                                  description: matchLabels is a map of {key,value}
                                    pairs. A single {key,value} in the matchLabels
                                    map is equivalent to an element of matchExpressions,
                                    whose key field is "key", the operator is "In",
                                    and the values array contains only "value". The
                                    requirements are ANDed.
                                  type: object
                              type: object
                              x-kubernetes-map-type: atomic
                            namespaces:
                              description: namespaces specifies a static list of namespace
                                names that the term applies to. The term is applied
                                to the union of the namespaces listed in this field
                                and the ones selected by namespaceSelector. null or
                                empty namespaces list and null namespaceSelector means
                                "this pod's namespace".
                              items:
                                type: string
                              type: array
                            topologyKey:
                              description: This pod should be co-located (affinity)
                                or not co-located (anti-affinity) with the pods matching
                                the labelSelector in the specified namespaces, where
                                co-located is defined as running on a node whose value
                                of the label with key topologyKey matches that of
                                any node on which any of the selected pods is running.
                                Empty topologyKey is not allowed.
                              type: string
                          required:
                          - topologyKey
                          type: object
                        type: array
                    type: object
                  podAntiAffinity:
                    description: Describes pod anti-affinity scheduling rules (e.g.
                      avoid putting this pod in the same node, zone, etc. as some
                      other pod(s)).
                    properties:
                      preferredDuringSchedulingIgnoredDuringExecution:
                        description: The scheduler will prefer to schedule pods to
                          nodes that satisfy the anti-affinity expressions specified
                          by this field, but it may choose a node that violates one
                          or more of the expressions. The node that is most preferred
                          is the one with the greatest sum of weights, i.e. for each
                          node that meets all of the scheduling requirements (resource
                          request, requiredDuringScheduling anti-affinity expressions,
                          etc.), compute a sum by iterating through the elements of
                          this field and adding "weight" to the sum if the node has
                          pods which matches the corresponding podAffinityTerm; the
                          node(s) with the highest sum are the most preferred.
                        items:
                          description: The weights of all of the matched WeightedPodAffinityTerm
                            fields are added per-node to find the most preferred node(s)
                          properties:
                            podAffinityTerm:
                              description: Required. A pod affinity term, associated
                                with the corresponding weight.
                              properties:
                                labelSelector:
                                  description: A label query over a set of resources,
                                    in this case pods. If it's null, this PodAffinityTerm
                                    matches with no Pods.
                                  properties:
                                    matchExpressions:
                                      description: matchExpressions is a list of label
                                        selector requirements. The requirements are
                                        ANDed.
                                      items:
                                        description: A label selector requirement
                                          is a selector that contains values, a key,
                                          and an operator that relates the key and
                                          values.
                                        properties:
                                          key:
                                            description: key is the label key that
                                              the selector applies to.
                                            type: string
                                          operator:
                                            description: operator represents a key's
                                              relationship to a set of values. Valid
                                              operators are In, NotIn, Exists and
                                              DoesNotExist.
                                            type: string
                                          values:
                                            description: values is an array of string
                                              values. If the operator is In or NotIn,
                                              the values array must be non-empty.
                                              If the operator is Exists or DoesNotExist,
                                              the values array must be empty. This
                                              array is replaced during a strategic
                                              merge patch.
                                            items:
                                              type: string
                                            type: array
                                        required:
                                        - key
                                        - operator
                                        type: object
                                      type: array
                                    matchLabels:
                                      additionalProperties:
                                        type: string
                                      description: matchLabels is a map of {key,value}
                                        pairs. A single {key,value} in the matchLabels
                                        map is equivalent to an element of matchExpressions,
                                        whose key field is "key", the operator is
                                        "In", and the values array contains only "value".
                                        The requirements are ANDed.
                                      type: object
                                  type: object
                                  x-kubernetes-map-type: atomic
                                matchLabelKeys:
                                  description: MatchLabelKeys is a set of pod label
                                    keys to select which pods will be taken into consideration.
                                    The keys are used to lookup values from the incoming
                                    pod labels, those key-value labels are merged
                                    with `LabelSelector` as `key in (value)` to select
                                    the group of existing pods which pods will be
                                    taken into consideration for the incoming pod's
                                    pod (anti) affinity. Keys that don't exist in
                                    the incoming pod labels will be ignored. The default
                                    value is empty. The same key is forbidden to exist
                                    in both MatchLabelKeys and LabelSelector. Also,
                                    MatchLabelKeys cannot be set when LabelSelector
                                    isn't set. This is an alpha field and requires
                                    enabling MatchLabelKeysInPodAffinity feature gate.
                                  items:
                                    type: string
                                  type: array
                                  x-kubernetes-list-type: atomic
                                mismatchLabelKeys:
                                  description: MismatchLabelKeys is a set of pod label
                                    keys to select which pods will be taken into consideration.
                                    The keys are used to lookup values from the incoming
                                    pod labels, those key-value labels are merged
                                    with `LabelSelector` as `key notin (value)` to
                                    select the group of existing pods which pods will
                                    be taken into consideration for the incoming pod's
                                    pod (anti) affinity. Keys that don't exist in
                                    the incoming pod labels will be ignored. The default
                                    value is empty. The same key is forbidden to exist
                                    in both MismatchLabelKeys and LabelSelector. Also,
                                    MismatchLabelKeys cannot be set when LabelSelector
                                    isn't set. This is an alpha field and requires
                                    enabling MatchLabelKeysInPodAffinity feature gate.
                                  items:
                                    type: string
                                  type: array
                                  x-kubernetes-list-type: atomic
                                namespaceSelector:
                                  description: A label query over the set of namespaces
                                    that the term applies to. The term is applied
                                    to the union of the namespaces selected by this
                                    field and the ones listed in the namespaces field.
                                    null selector and null or empty namespaces list
                                    means "this pod's namespace". An empty selector
                                    ({}) matches all namespaces.
                                  properties:
                                    matchExpressions:
                                      description: matchExpressions is a list of label
                                        selector requirements. The requirements are
                                        ANDed.
                                      items:
                                        description: A label selector requirement
                                          is a selector that contains values, a key,
                                          and an operator that relates the key and
                                          values.
                                        properties:
                                          key:
                                            description: key is the label key that
                                              the selector applies to.
                                            type: string
                                          operator:
                                            description: operator represents a key's
                                              relationship to a set of values. Valid
                                              operators are In, NotIn, Exists and
                                              DoesNotExist.
                                            type: string
                                          values:
                                            description: values is an array of string
                                              values. If the operator is In or NotIn,
                                              the values array must be non-empty.
                                              If the operator is Exists or DoesNotExist,
                                              the values array must be empty. This
                                              array is replaced during a strategic
                                              merge patch.
                                            items:
                                              type: string
                                            type: array
                                        required:
                                        - key
                                        - operator
                                        type: object
                                      type: array
                                    matchLabels:
                                      additionalProperties:
                                        type: string
                                      description: matchLabels is a map of {key,value}
                                        pairs. A single {key,value} in the matchLabels
                                        map is equivalent to an element of matchExpressions,
                                        whose key field is "key", the operator is
                                        "In", and the values array contains only "value".
                                        The requirements are ANDed.
                                      type: object
                                  type: object
                                  x-kubernetes-map-type: atomic
                                namespaces:
                                  description: namespaces specifies a static list
                                    of namespace names that the term applies to. The
                                    term is applied to the union of the namespaces
                                    listed in this field and the ones selected by
                                    namespaceSelector. null or empty namespaces list
                                    and null namespaceSelector means "this pod's namespace".
                                  items:
                                    type: string
                                  type: array
                                topologyKey:
                                  description: This pod should be co-located (affinity)
                                    or not co-located (anti-affinity) with the pods
                                    matching the labelSelector in the specified namespaces,
                                    where co-located is defined as running on a node
                                    whose value of the label with key topologyKey
                                    matches that of any node on which any of the selected
                                    pods is running. Empty topologyKey is not allowed.
                                  type: string
                              required:
                              - topologyKey
                              type: object
                            weight:
                              description: weight associated with matching the corresponding
                                podAffinityTerm, in the range 1-100.
                              format: int32
                              type: integer
                          required:
                          - podAffinityTerm
                          - weight
                          type: object
                        type: array
                      requiredDuringSchedulingIgnoredDuringExecution:
                        description: If the anti-affinity requirements specified by
                          this field are not met at scheduling time, the pod will
                          not be scheduled onto the node. If the anti-affinity requirements
                          specified by this field cease to be met at some point during
                          pod execution (e.g. due to a pod label update), the system
                          may or may not try to eventually evict the pod from its
                          node. When there are multiple elements, the lists of nodes
                          corresponding to each podAffinityTerm are intersected, i.e.
                          all terms must be satisfied.
                        items:
                          description: Defines a set of pods (namely those matching
                            the labelSelector relative to the given namespace(s))
                            that this pod should be co-located (affinity) or not co-located
                            (anti-affinity) with, where co-located is defined as running
                            on a node whose value of the label with key <topologyKey>
                            matches that of any node on which a pod of the set of
                            pods is running
                          properties:
                            labelSelector:
                              description: A label query over a set of resources,
                                in this case pods. If it's null, this PodAffinityTerm
                                matches with no Pods.
                              properties:
                                matchExpressions:
                                  description: matchExpressions is a list of label
                                    selector requirements. The requirements are ANDed.
                                  items:
                                    description: A label selector requirement is a
                                      selector that contains values, a key, and an
                                      operator that relates the key and values.
                                    properties:
                                      key:
                                        description: key is the label key that the
                                          selector applies to.
                                        type: string
                                      operator:
                                        description: operator represents a key's relationship
                                          to a set of values. Valid operators are
                                          In, NotIn, Exists and DoesNotExist.
                                        type: string
                                      values:
                                        description: values is an array of string
                                          values. If the operator is In or NotIn,
                                          the values array must be non-empty. If the
                                          operator is Exists or DoesNotExist, the
                                          values array must be empty. This array is
                                          replaced during a strategic merge patch.
                                        items:
                                          type: string
                                        type: array
                                    required:
                                    - key
                                    - operator
                                    type: object
                                  type: array
                                matchLabels:
                                  additionalProperties:
                                    type: string
                                  description: matchLabels is a map of {key,value}
                                    pairs. A single {key,value} in the matchLabels
                                    map is equivalent to an element of matchExpressions,
                                    whose key field is "key", the operator is "In",
                                    and the values array contains only "value". The
                                    requirements are ANDed.
                                  type: object
                              type: object
                              x-kubernetes-map-type: atomic
                            matchLabelKeys:
                              description: MatchLabelKeys is a set of pod label keys
                                to select which pods will be taken into consideration.
                                The keys are used to lookup values from the incoming
                                pod labels, those key-value labels are merged with
                                `LabelSelector` as `key in (value)` to select the
                                group of existing pods which pods will be taken into
                                consideration for the incoming pod's pod (anti) affinity.
                                Keys that don't exist in the incoming pod labels will
                                be ignored. The default value is empty. The same key
                                is forbidden to exist in both MatchLabelKeys and LabelSelector.
                                Also, MatchLabelKeys cannot be set when LabelSelector
                                isn't set. This is an alpha field and requires enabling
                                MatchLabelKeysInPodAffinity feature gate.
                              items:
                                type: string
                              type: array
                              x-kubernetes-list-type: atomic
                            mismatchLabelKeys:
                              description: MismatchLabelKeys is a set of pod label
                                keys to select which pods will be taken into consideration.
                                The keys are used to lookup values from the incoming
                                pod labels, those key-value labels are merged with
                                `LabelSelector` as `key notin (value)` to select the
                                group of existing pods which pods will be taken into
                                consideration for the incoming pod's pod (anti) affinity.
                                Keys that don't exist in the incoming pod labels will
                                be ignored. The default value is empty. The same key
                                is forbidden to exist in both MismatchLabelKeys and
                                LabelSelector. Also, MismatchLabelKeys cannot be set
                                when LabelSelector isn't set. This is an alpha field
                                and requires enabling MatchLabelKeysInPodAffinity
                                feature gate.
                              items:
                                type: string
                              type: array
                              x-kubernetes-list-type: atomic
                            namespaceSelector:
                              description: A label query over the set of namespaces
                                that the term applies to. The term is applied to the
                                union of the namespaces selected by this field and
                                the ones listed in the namespaces field. null selector
                                and null or empty namespaces list means "this pod's
                                namespace". An empty selector ({}) matches all namespaces.
                              properties:
                                matchExpressions:
                                  description: matchExpressions is a list of label
                                    selector requirements. The requirements are ANDed.
                                  items:
                                    description: A label selector requirement is a
                                      selector that contains values, a key, and an
                                      operator that relates the key and values.
                                    properties:
                                      key:
                                        description: key is the label key that the
                                          selector applies to.
                                        type: string
                                      operator:
                                        description: operator represents a key's relationship
                                          to a set of values. Valid operators are
                                          In, NotIn, Exists and DoesNotExist.
                                        type: string
                                      values:
                                        description: values is an array of string
                                          values. If the operator is In or NotIn,
                                          the values array must be non-empty. If the
                                          operator is Exists or DoesNotExist, the
                                          values array must be empty. This array is
                                          replaced during a strategic merge patch.
                                        items:
                                          type: string
                                        type: array
                                    required:
                                    - key
                                    - operator
                                    type: object
                                  type: array
                                matchLabels:
                                  additionalProperties:
                                    type: string
                                  description: matchLabels is a map of {key,value}
                                    pairs. A single {key,value} in the matchLabels
                                    map is equivalent to an element of matchExpressions,
                                    whose key field is "key", the operator is "In",
                                    and the values array contains only "value". The
                                    requirements are ANDed.
                                  type: object
                              type: object
                              x-kubernetes-map-type: atomic
                            namespaces:
                              description: namespaces specifies a static list of namespace
                                names that the term applies to. The term is applied
                                to the union of the namespaces listed in this field
                                and the ones selected by namespaceSelector. null or
                                empty namespaces list and null namespaceSelector means
                                "this pod's namespace".
                              items:
                                type: string
                              type: array
                            topologyKey:
                              description: This pod should be co-located (affinity)
                                or not co-located (anti-affinity) with the pods matching
                                the labelSelector in the specified namespaces, where
                                co-located is defined as running on a node whose value
                                of the label with key topologyKey matches that of
                                any node on which any of the selected pods is running.
                                Empty topologyKey is not allowed.
                              type: string
                          required:
                          - topologyKey
                          type: object
                        type: array
                    type: object
                type: object
              delayStartSeconds:
                default: 30
                description: DelayStartSeconds is the time the init container (`setup-container`)
                  will sleep before terminating. This effectively delays the time
                  between starting the Pod and starting the `rabbitmq` container.
                  RabbitMQ relies on up-to-date DNS entries early during peer discovery.
                  The purpose of this artificial delay is to ensure that DNS entries
                  are up-to-date when booting RabbitMQ. For more information, see
                  https://github.com/kubernetes/kubernetes/issues/92559 If your Kubernetes
                  DNS backend is configured with a low DNS cache value or publishes
                  not ready addresses promptly, you can decrase this value or set
                  it to 0.
                format: int32
                minimum: 0
                type: integer
              image:
                description: Image is the name of the RabbitMQ docker image to use
                  for RabbitMQ nodes in the RabbitmqCluster. Must be provided together
                  with ImagePullSecrets in order to use an image in a private registry.
                type: string
              imagePullSecrets:
                description: List of Secret resource containing access credentials
                  to the registry for the RabbitMQ image. Required if the docker registry
                  is private.
                items:
                  description: LocalObjectReference contains enough information to
                    let you locate the referenced object inside the same namespace.
                  properties:
                    name:
                      description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names
                        TODO: Add other useful fields. apiVersion, kind, uid?'
                      type: string
                  type: object
                  x-kubernetes-map-type: atomic
                type: array
              override:
                properties:
                  service:
                    properties:
                      metadata:
                        properties:
                          annotations:
                            additionalProperties:
                              type: string
                            type: object
                          labels:
                            additionalProperties:
                              type: string
                            type: object
                        type: object
                      spec:
                        properties:
                          allocateLoadBalancerNodePorts:
                            type: boolean
                          clusterIP:
                            type: string
                          clusterIPs:
                            items:
                              type: string
                            type: array
                            x-kubernetes-list-type: atomic
                          externalIPs:
                            items:
                              type: string
                            type: array
                          externalName:
                            type: string
                          externalTrafficPolicy:
                            type: string
                          healthCheckNodePort:
                            format: int32
                            type: integer
                          internalTrafficPolicy:
                            type: string
                          ipFamilies:
                            items:
                              type: string
                            type: array
                            x-kubernetes-list-type: atomic
                          ipFamilyPolicy:
                            type: string
                          loadBalancerClass:
                            type: string
                          loadBalancerIP:
                            type: string
                          loadBalancerSourceRanges:
                            items:
                              type: string
                            type: array
                          ports:
                            items:
                              properties:
                                appProtocol:
                                  type: string
                                name:
                                  type: string
                                nodePort:
                                  format: int32
                                  type: integer
                                port:
                                  format: int32
                                  type: integer
                                protocol:
                                  default: TCP
                                  type: string
                                targetPort:
                                  anyOf:
                                  - type: integer
                                  - type: string
                                  x-kubernetes-int-or-string: true
                              required:
                              - port
                              type: object
                            type: array
                            x-kubernetes-list-map-keys:
                            - port
                            - protocol
                            x-kubernetes-list-type: map
                          publishNotReadyAddresses:
                            type: boolean
                          selector:
                            additionalProperties:
                              type: string
                            type: object
                            x-kubernetes-map-type: atomic
                          sessionAffinity:
                            type: string
                          sessionAffinityConfig:
                            properties:
                              clientIP:
                                properties:
                                  timeoutSeconds:
                                    format: int32
                                    type: integer
                                type: object
                            type: object
                          type:
                            type: string
                        type: object
                    type: object
                  statefulSet:
                    properties:
                      metadata:
                        properties:
                          annotations:
                            additionalProperties:
                              type: string
                            type: object
                          labels:
                            additionalProperties:
                              type: string
                            type: object
                        type: object
                      spec:
                        properties:
                          minReadySeconds:
                            format: int32
                            type: integer
                          persistentVolumeClaimRetentionPolicy:
                            properties:
                              whenDeleted:
                                type: string
                              whenScaled:
                                type: string
                            type: object
                          podManagementPolicy:
                            type: string
                          replicas:
                            format: int32
                            type: integer
                          selector:
                            properties:
                              matchExpressions:
                                items:
                                  properties:
                                    key:
                                      type: string
                                    operator:
                                      type: string
                                    values:
                                      items:
                                        type: string
                                      type: array
                                  required:
                                  - key
                                  - operator
                                  type: object
                                type: array
                              matchLabels:
                                additionalProperties:
                                  type: string
                                type: object
                            type: object
                            x-kubernetes-map-type: atomic
                          serviceName:
                            type: string
                          template:
                            properties:
                              metadata:
                                properties:
                                  annotations:
                                    additionalProperties:
                                      type: string
                                    type: object
                                  labels:
                                    additionalProperties:
                                      type: string
                                    type: object
                                  name:
                                    type: string
                                  namespace:
                                    type: string
                                type: object
                              spec:
                                properties:
                                  activeDeadlineSeconds:
                                    format: int64
                                    type: integer
                                  affinity:
                                    properties:
                                      nodeAffinity:
                                        properties:
                                          preferredDuringSchedulingIgnoredDuringExecution:
                                            items:
                                              properties:
                                                preference:
                                                  properties:
                                                    matchExpressions:
                                                      items:
                                                        properties:
                                                          key:
                                                            type: string
                                                          operator:
                                                            type: string
                                                          values:
                                                            items:
                                                              type: string
                                                            type: array
                                                        required:
                                                        - key
                                                        - operator
                                                        type: object
                                                      type: array
                                                    matchFields:
                                                      items:
                                                        properties:
                                                          key:
                                                            type: string
                                                          operator:
                                                            type: string
                                                          values:
                                                            items:
                                                              type: string
                                                            type: array
                                                        required:
                                                        - key
                                                        - operator
                                                        type: object
                                                      type: array
                                                  type: object
                                                  x-kubernetes-map-type: atomic
                                                weight:
                                                  format: int32
                                                  type: integer
                                              required:
                                              - preference
                                              - weight
                                              type: object
                                            type: array
                                          requiredDuringSchedulingIgnoredDuringExecution:
                                            properties:
                                              nodeSelectorTerms:
                                                items:
                                                  properties:
                                                    matchExpressions:
                                                      items:
                                                        properties:
                                                          key:
                                                            type: string
                                                          operator:
                                                            type: string
                                                          values:
                                                            items:
                                                              type: string
                                                            type: array
                                                        required:
                                                        - key
                                                        - operator
                                                        type: object
                                                      type: array
                                                    matchFields:
                                                      items:
                                                        properties:
                                                          key:
                                                            type: string
                                                          operator:
                                                            type: string
                                                          values:
                                                            items:
                                                              type: string
                                                            type: array
                                                        required:
                                                        - key
                                                        - operator
                                                        type: object
                                                      type: array
                                                  type: object
                                                  x-kubernetes-map-type: atomic
                                                type: array
                                            required:
                                            - nodeSelectorTerms
                                            type: object
                                            x-kubernetes-map-type: atomic
                                        type: object
                                      podAffinity:
                                        properties:
                                          preferredDuringSchedulingIgnoredDuringExecution:
                                            items:
                                              properties:
                                                podAffinityTerm:
                                                  properties:
                                                    labelSelector:
                                                      properties:
                                                        matchExpressions:
                                                          items:
                                                            properties:
                                                              key:
                                                                type: string
                                                              operator:
                                                                type: string
                                                              values:
                                                                items:
                                                                  type: string
                                                                type: array
                                                            required:
                                                            - key
                                                            - operator
                                                            type: object
                                                          type: array
                                                        matchLabels:
                                                          additionalProperties:
                                                            type: string
                                                          type: object
                                                      type: object
                                                      x-kubernetes-map-type: atomic
                                                    matchLabelKeys:
                                                      items:
                                                        type: string
                                                      type: array
                                                      x-kubernetes-list-type: atomic
                                                    mismatchLabelKeys:
                                                      items:
                                                        type: string
                                                      type: array
                                                      x-kubernetes-list-type: atomic
                                                    namespaceSelector:
                                                      properties:
                                                        matchExpressions:
                                                          items:
                                                            properties:
                                                              key:
                                                                type: string
                                                              operator:
                                                                type: string
                                                              values:
                                                                items:
                                                                  type: string
                                                                type: array
                                                            required:
                                                            - key
                                                            - operator
                                                            type: object
                                                          type: array
                                                        matchLabels:
                                                          additionalProperties:
                                                            type: string
                                                          type: object
                                                      type: object
                                                      x-kubernetes-map-type: atomic
                                                    namespaces:
                                                      items:
                                                        type: string
                                                      type: array
                                                    topologyKey:
                                                      type: string
                                                  required:
                                                  - topologyKey
                                                  type: object
                                                weight:
                                                  format: int32
                                                  type: integer
                                              required:
                                              - podAffinityTerm
                                              - weight
                                              type: object
                                            type: array
                                          requiredDuringSchedulingIgnoredDuringExecution:
                                            items:
                                              properties:
                                                labelSelector:
                                                  properties:
                                                    matchExpressions:
                                                      items:
                                                        properties:
                                                          key:
                                                            type: string
                                                          operator:
                                                            type: string
                                                          values:
                                                            items:
                                                              type: string
                                                            type: array
                                                        required:
                                                        - key
                                                        - operator
                                                        type: object
                                                      type: array
                                                    matchLabels:
                                                      additionalProperties:
                                                        type: string
                                                      type: object
                                                  type: object
                                                  x-kubernetes-map-type: atomic
                                                matchLabelKeys:
                                                  items:
                                                    type: string
                                                  type: array
                                                  x-kubernetes-list-type: atomic
                                                mismatchLabelKeys:
                                                  items:
                                                    type: string
                                                  type: array
                                                  x-kubernetes-list-type: atomic
                                                namespaceSelector:
                                                  properties:
                                                    matchExpressions:
                                                      items:
                                                        properties:
                                                          key:
                                                            type: string
                                                          operator:
                                                            type: string
                                                          values:
                                                            items:
                                                              type: string
                                                            type: array
                                                        required:
                                                        - key
                                                        - operator
                                                        type: object
                                                      type: array
                                                    matchLabels:
                                                      additionalProperties:
                                                        type: string
                                                      type: object
                                                  type: object
                                                  x-kubernetes-map-type: atomic
                                                namespaces:
                                                  items:
                                                    type: string
                                                  type: array
                                                topologyKey:
                                                  type: string
                                              required:
                                              - topologyKey
                                              type: object
                                            type: array
                                        type: object
                                      podAntiAffinity:
                                        properties:
                                          preferredDuringSchedulingIgnoredDuringExecution:
                                            items:
                                              properties:
                                                podAffinityTerm:
                                                  properties:
                                                    labelSelector:
                                                      properties:
                                                        matchExpressions:
                                                          items:
                                                            properties:
                                                              key:
                                                                type: string
                                                              operator:
                                                                type: string
                                                              values:
                                                                items:
                                                                  type: string
                                                                type: array
                                                            required:
                                                            - key
                                                            - operator
                                                            type: object
                                                          type: array
                                                        matchLabels:
                                                          additionalProperties:
                                                            type: string
                                                          type: object
                                                      type: object
                                                      x-kubernetes-map-type: atomic
                                                    matchLabelKeys:
                                                      items:
                                                        type: string
                                                      type: array
                                                      x-kubernetes-list-type: atomic
                                                    mismatchLabelKeys:
                                                      items:
                                                        type: string
                                                      type: array
                                                      x-kubernetes-list-type: atomic
                                                    namespaceSelector:
                                                      properties:
                                                        matchExpressions:
                                                          items:
                                                            properties:
                                                              key:
                                                                type: string
                                                              operator:
                                                                type: string
                                                              values:
                                                                items:
                                                                  type: string
                                                                type: array
                                                            required:
                                                            - key
                                                            - operator
                                                            type: object
                                                          type: array
                                                        matchLabels:
                                                          additionalProperties:
                                                            type: string
                                                          type: object
                                                      type: object
                                                      x-kubernetes-map-type: atomic
                                                    namespaces:
                                                      items:
                                                        type: string
                                                      type: array
                                                    topologyKey:
                                                      type: string
                                                  required:
                                                  - topologyKey
                                                  type: object
                                                weight:
                                                  format: int32
                                                  type: integer
                                              required:
                                              - podAffinityTerm
                                              - weight
                                              type: object
                                            type: array
                                          requiredDuringSchedulingIgnoredDuringExecution:
                                            items:
                                              properties:
                                                labelSelector:
                                                  properties:
                                                    matchExpressions:
                                                      items:
                                                        properties:
                                                          key:
                                                            type: string
                                                          operator:
                                                            type: string
                                                          values:
                                                            items:
                                                              type: string
                                                            type: array
                                                        required:
                                                        - key
                                                        - operator
                                                        type: object
                                                      type: array
                                                    matchLabels:
                                                      additionalProperties:
                                                        type: string
                                                      type: object
                                                  type: object
                                                  x-kubernetes-map-type: atomic
                                                matchLabelKeys:
                                                  items:
                                                    type: string
                                                  type: array
                                                  x-kubernetes-list-type: atomic
                                                mismatchLabelKeys:
                                                  items:
                                                    type: string
                                                  type: array
                                                  x-kubernetes-list-type: atomic
                                                namespaceSelector:
                                                  properties:
                                                    matchExpressions:
                                                      items:
                                                        properties:
                                                          key:
                                                            type: string
                                                          operator:
                                                            type: string
                                                          values:
                                                            items:
                                                              type: string
                                                            type: array
                                                        required:
                                                        - key
                                                        - operator
                                                        type: object
                                                      type: array
                                                    matchLabels:
                                                      additionalProperties:
                                                        type: string
                                                      type: object
                                                  type: object
                                                  x-kubernetes-map-type: atomic
                                                namespaces:
                                                  items:
                                                    type: string
                                                  type: array
                                                topologyKey:
                                                  type: string
                                              required:
                                              - topologyKey
                                              type: object
                                            type: array
                                        type: object
                                    type: object
                                  automountServiceAccountToken:
                                    type: boolean
                                  containers:
                                    items:
                                      properties:
                                        args:
                                          items:
                                            type: string
                                          type: array
                                        command:
                                          items:
                                            type: string
                                          type: array
                                        env:
                                          items:
                                            properties:
                                              name:
                                                type: string
                                              value:
                                                type: string
                                              valueFrom:
                                                properties:
                                                  configMapKeyRef:
                                                    properties:
                                                      key:
                                                        type: string
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                    required:
                                                    - key
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  fieldRef:
                                                    properties:
                                                      apiVersion:
                                                        type: string
                                                      fieldPath:
                                                        type: string
                                                    required:
                                                    - fieldPath
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  resourceFieldRef:
                                                    properties:
                                                      containerName:
                                                        type: string
                                                      divisor:
                                                        anyOf:
                                                        - type: integer
                                                        - type: string
                                                        pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                        x-kubernetes-int-or-string: true
                                                      resource:
                                                        type: string
                                                    required:
                                                    - resource
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  secretKeyRef:
                                                    properties:
                                                      key:
                                                        type: string
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                    required:
                                                    - key
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                type: object
                                            required:
                                            - name
                                            type: object
                                          type: array
                                        envFrom:
                                          items:
                                            properties:
                                              configMapRef:
                                                properties:
                                                  name:
                                                    type: string
                                                  optional:
                                                    type: boolean
                                                type: object
                                                x-kubernetes-map-type: atomic
                                              prefix:
                                                type: string
                                              secretRef:
                                                properties:
                                                  name:
                                                    type: string
                                                  optional:
                                                    type: boolean
                                                type: object
                                                x-kubernetes-map-type: atomic
                                            type: object
                                          type: array
                                        image:
                                          type: string
                                        imagePullPolicy:
                                          type: string
                                        lifecycle:
                                          properties:
                                            postStart:
                                              properties:
                                                exec:
                                                  properties:
                                                    command:
                                                      items:
                                                        type: string
                                                      type: array
                                                  type: object
                                                httpGet:
                                                  properties:
                                                    host:
                                                      type: string
                                                    httpHeaders:
                                                      items:
                                                        properties:
                                                          name:
                                                            type: string
                                                          value:
                                                            type: string
                                                        required:
                                                        - name
                                                        - value
                                                        type: object
                                                      type: array
                                                    path:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                    scheme:
                                                      type: string
                                                  required:
                                                  - port
                                                  type: object
                                                sleep:
                                                  properties:
                                                    seconds:
                                                      format: int64
                                                      type: integer
                                                  required:
                                                  - seconds
                                                  type: object
                                                tcpSocket:
                                                  properties:
                                                    host:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                  required:
                                                  - port
                                                  type: object
                                              type: object
                                            preStop:
                                              properties:
                                                exec:
                                                  properties:
                                                    command:
                                                      items:
                                                        type: string
                                                      type: array
                                                  type: object
                                                httpGet:
                                                  properties:
                                                    host:
                                                      type: string
                                                    httpHeaders:
                                                      items:
                                                        properties:
                                                          name:
                                                            type: string
                                                          value:
                                                            type: string
                                                        required:
                                                        - name
                                                        - value
                                                        type: object
                                                      type: array
                                                    path:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                    scheme:
                                                      type: string
                                                  required:
                                                  - port
                                                  type: object
                                                sleep:
                                                  properties:
                                                    seconds:
                                                      format: int64
                                                      type: integer
                                                  required:
                                                  - seconds
                                                  type: object
                                                tcpSocket:
                                                  properties:
                                                    host:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                  required:
                                                  - port
                                                  type: object
                                              type: object
                                          type: object
                                        livenessProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        name:
                                          type: string
                                        ports:
                                          items:
                                            properties:
                                              containerPort:
                                                format: int32
                                                type: integer
                                              hostIP:
                                                type: string
                                              hostPort:
                                                format: int32
                                                type: integer
                                              name:
                                                type: string
                                              protocol:
                                                default: TCP
                                                type: string
                                            required:
                                            - containerPort
                                            type: object
                                          type: array
                                          x-kubernetes-list-map-keys:
                                          - containerPort
                                          - protocol
                                          x-kubernetes-list-type: map
                                        readinessProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        resizePolicy:
                                          items:
                                            properties:
                                              resourceName:
                                                type: string
                                              restartPolicy:
                                                type: string
                                            required:
                                            - resourceName
                                            - restartPolicy
                                            type: object
                                          type: array
                                          x-kubernetes-list-type: atomic
                                        resources:
                                          properties:
                                            claims:
                                              items:
                                                properties:
                                                  name:
                                                    type: string
                                                required:
                                                - name
                                                type: object
                                              type: array
                                              x-kubernetes-list-map-keys:
                                              - name
                                              x-kubernetes-list-type: map
                                            limits:
                                              additionalProperties:
                                                anyOf:
                                                - type: integer
                                                - type: string
                                                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                x-kubernetes-int-or-string: true
                                              type: object
                                            requests:
                                              additionalProperties:
                                                anyOf:
                                                - type: integer
                                                - type: string
                                                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                x-kubernetes-int-or-string: true
                                              type: object
                                          type: object
                                        restartPolicy:
                                          type: string
                                        securityContext:
                                          properties:
                                            allowPrivilegeEscalation:
                                              type: boolean
                                            capabilities:
                                              properties:
                                                add:
                                                  items:
                                                    type: string
                                                  type: array
                                                drop:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            privileged:
                                              type: boolean
                                            procMount:
                                              type: string
                                            readOnlyRootFilesystem:
                                              type: boolean
                                            runAsGroup:
                                              format: int64
                                              type: integer
                                            runAsNonRoot:
                                              type: boolean
                                            runAsUser:
                                              format: int64
                                              type: integer
                                            seLinuxOptions:
                                              properties:
                                                level:
                                                  type: string
                                                role:
                                                  type: string
                                                type:
                                                  type: string
                                                user:
                                                  type: string
                                              type: object
                                            seccompProfile:
                                              properties:
                                                localhostProfile:
                                                  type: string
                                                type:
                                                  type: string
                                              required:
                                              - type
                                              type: object
                                            windowsOptions:
                                              properties:
                                                gmsaCredentialSpec:
                                                  type: string
                                                gmsaCredentialSpecName:
                                                  type: string
                                                hostProcess:
                                                  type: boolean
                                                runAsUserName:
                                                  type: string
                                              type: object
                                          type: object
                                        startupProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        stdin:
                                          type: boolean
                                        stdinOnce:
                                          type: boolean
                                        terminationMessagePath:
                                          type: string
                                        terminationMessagePolicy:
                                          type: string
                                        tty:
                                          type: boolean
                                        volumeDevices:
                                          items:
                                            properties:
                                              devicePath:
                                                type: string
                                              name:
                                                type: string
                                            required:
                                            - devicePath
                                            - name
                                            type: object
                                          type: array
                                        volumeMounts:
                                          items:
                                            properties:
                                              mountPath:
                                                type: string
                                              mountPropagation:
                                                type: string
                                              name:
                                                type: string
                                              readOnly:
                                                type: boolean
                                              subPath:
                                                type: string
                                              subPathExpr:
                                                type: string
                                            required:
                                            - mountPath
                                            - name
                                            type: object
                                          type: array
                                        workingDir:
                                          type: string
                                      required:
                                      - name
                                      type: object
                                    type: array
                                  dnsConfig:
                                    properties:
                                      nameservers:
                                        items:
                                          type: string
                                        type: array
                                      options:
                                        items:
                                          properties:
                                            name:
                                              type: string
                                            value:
                                              type: string
                                          type: object
                                        type: array
                                      searches:
                                        items:
                                          type: string
                                        type: array
                                    type: object
                                  dnsPolicy:
                                    type: string
                                  enableServiceLinks:
                                    type: boolean
                                  ephemeralContainers:
                                    items:
                                      properties:
                                        args:
                                          items:
                                            type: string
                                          type: array
                                        command:
                                          items:
                                            type: string
                                          type: array
                                        env:
                                          items:
                                            properties:
                                              name:
                                                type: string
                                              value:
                                                type: string
                                              valueFrom:
                                                properties:
                                                  configMapKeyRef:
                                                    properties:
                                                      key:
                                                        type: string
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                    required:
                                                    - key
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  fieldRef:
                                                    properties:
                                                      apiVersion:
                                                        type: string
                                                      fieldPath:
                                                        type: string
                                                    required:
                                                    - fieldPath
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  resourceFieldRef:
                                                    properties:
                                                      containerName:
                                                        type: string
                                                      divisor:
                                                        anyOf:
                                                        - type: integer
                                                        - type: string
                                                        pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                        x-kubernetes-int-or-string: true
                                                      resource:
                                                        type: string
                                                    required:
                                                    - resource
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  secretKeyRef:
                                                    properties:
                                                      key:
                                                        type: string
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                    required:
                                                    - key
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                type: object
                                            required:
                                            - name
                                            type: object
                                          type: array
                                        envFrom:
                                          items:
                                            properties:
                                              configMapRef:
                                                properties:
                                                  name:
                                                    type: string
                                                  optional:
                                                    type: boolean
                                                type: object
                                                x-kubernetes-map-type: atomic
                                              prefix:
                                                type: string
                                              secretRef:
                                                properties:
                                                  name:
                                                    type: string
                                                  optional:
                                                    type: boolean
                                                type: object
                                                x-kubernetes-map-type: atomic
                                            type: object
                                          type: array
                                        image:
                                          type: string
                                        imagePullPolicy:
                                          type: string
                                        lifecycle:
                                          properties:
                                            postStart:
                                              properties:
                                                exec:
                                                  properties:
                                                    command:
                                                      items:
                                                        type: string
                                                      type: array
                                                  type: object
                                                httpGet:
                                                  properties:
                                                    host:
                                                      type: string
                                                    httpHeaders:
                                                      items:
                                                        properties:
                                                          name:
                                                            type: string
                                                          value:
                                                            type: string
                                                        required:
                                                        - name
                                                        - value
                                                        type: object
                                                      type: array
                                                    path:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                    scheme:
                                                      type: string
                                                  required:
                                                  - port
                                                  type: object
                                                sleep:
                                                  properties:
                                                    seconds:
                                                      format: int64
                                                      type: integer
                                                  required:
                                                  - seconds
                                                  type: object
                                                tcpSocket:
                                                  properties:
                                                    host:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                  required:
                                                  - port
                                                  type: object
                                              type: object
                                            preStop:
                                              properties:
                                                exec:
                                                  properties:
                                                    command:
                                                      items:
                                                        type: string
                                                      type: array
                                                  type: object
                                                httpGet:
                                                  properties:
                                                    host:
                                                      type: string
                                                    httpHeaders:
                                                      items:
                                                        properties:
                                                          name:
                                                            type: string
                                                          value:
                                                            type: string
                                                        required:
                                                        - name
                                                        - value
                                                        type: object
                                                      type: array
                                                    path:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                    scheme:
                                                      type: string
                                                  required:
                                                  - port
                                                  type: object
                                                sleep:
                                                  properties:
                                                    seconds:
                                                      format: int64
                                                      type: integer
                                                  required:
                                                  - seconds
                                                  type: object
                                                tcpSocket:
                                                  properties:
                                                    host:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                  required:
                                                  - port
                                                  type: object
                                              type: object
                                          type: object
                                        livenessProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        name:
                                          type: string
                                        ports:
                                          items:
                                            properties:
                                              containerPort:
                                                format: int32
                                                type: integer
                                              hostIP:
                                                type: string
                                              hostPort:
                                                format: int32
                                                type: integer
                                              name:
                                                type: string
                                              protocol:
                                                default: TCP
                                                type: string
                                            required:
                                            - containerPort
                                            type: object
                                          type: array
                                          x-kubernetes-list-map-keys:
                                          - containerPort
                                          - protocol
                                          x-kubernetes-list-type: map
                                        readinessProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        resizePolicy:
                                          items:
                                            properties:
                                              resourceName:
                                                type: string
                                              restartPolicy:
                                                type: string
                                            required:
                                            - resourceName
                                            - restartPolicy
                                            type: object
                                          type: array
                                          x-kubernetes-list-type: atomic
                                        resources:
                                          properties:
                                            claims:
                                              items:
                                                properties:
                                                  name:
                                                    type: string
                                                required:
                                                - name
                                                type: object
                                              type: array
                                              x-kubernetes-list-map-keys:
                                              - name
                                              x-kubernetes-list-type: map
                                            limits:
                                              additionalProperties:
                                                anyOf:
                                                - type: integer
                                                - type: string
                                                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                x-kubernetes-int-or-string: true
                                              type: object
                                            requests:
                                              additionalProperties:
                                                anyOf:
                                                - type: integer
                                                - type: string
                                                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                x-kubernetes-int-or-string: true
                                              type: object
                                          type: object
                                        restartPolicy:
                                          type: string
                                        securityContext:
                                          properties:
                                            allowPrivilegeEscalation:
                                              type: boolean
                                            capabilities:
                                              properties:
                                                add:
                                                  items:
                                                    type: string
                                                  type: array
                                                drop:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            privileged:
                                              type: boolean
                                            procMount:
                                              type: string
                                            readOnlyRootFilesystem:
                                              type: boolean
                                            runAsGroup:
                                              format: int64
                                              type: integer
                                            runAsNonRoot:
                                              type: boolean
                                            runAsUser:
                                              format: int64
                                              type: integer
                                            seLinuxOptions:
                                              properties:
                                                level:
                                                  type: string
                                                role:
                                                  type: string
                                                type:
                                                  type: string
                                                user:
                                                  type: string
                                              type: object
                                            seccompProfile:
                                              properties:
                                                localhostProfile:
                                                  type: string
                                                type:
                                                  type: string
                                              required:
                                              - type
                                              type: object
                                            windowsOptions:
                                              properties:
                                                gmsaCredentialSpec:
                                                  type: string
                                                gmsaCredentialSpecName:
                                                  type: string
                                                hostProcess:
                                                  type: boolean
                                                runAsUserName:
                                                  type: string
                                              type: object
                                          type: object
                                        startupProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        stdin:
                                          type: boolean
                                        stdinOnce:
                                          type: boolean
                                        targetContainerName:
                                          type: string
                                        terminationMessagePath:
                                          type: string
                                        terminationMessagePolicy:
                                          type: string
                                        tty:
                                          type: boolean
                                        volumeDevices:
                                          items:
                                            properties:
                                              devicePath:
                                                type: string
                                              name:
                                                type: string
                                            required:
                                            - devicePath
                                            - name
                                            type: object
                                          type: array
                                        volumeMounts:
                                          items:
                                            properties:
                                              mountPath:
                                                type: string
                                              mountPropagation:
                                                type: string
                                              name:
                                                type: string
                                              readOnly:
                                                type: boolean
                                              subPath:
                                                type: string
                                              subPathExpr:
                                                type: string
                                            required:
                                            - mountPath
                                            - name
                                            type: object
                                          type: array
                                        workingDir:
                                          type: string
                                      required:
                                      - name
                                      type: object
                                    type: array
                                  hostAliases:
                                    items:
                                      properties:
                                        hostnames:
                                          items:
                                            type: string
                                          type: array
                                        ip:
                                          type: string
                                      type: object
                                    type: array
                                  hostIPC:
                                    type: boolean
                                  hostNetwork:
                                    type: boolean
                                  hostPID:
                                    type: boolean
                                  hostUsers:
                                    type: boolean
                                  hostname:
                                    type: string
                                  imagePullSecrets:
                                    items:
                                      properties:
                                        name:
                                          type: string
                                      type: object
                                      x-kubernetes-map-type: atomic
                                    type: array
                                  initContainers:
                                    items:
                                      properties:
                                        args:
                                          items:
                                            type: string
                                          type: array
                                        command:
                                          items:
                                            type: string
                                          type: array
                                        env:
                                          items:
                                            properties:
                                              name:
                                                type: string
                                              value:
                                                type: string
                                              valueFrom:
                                                properties:
                                                  configMapKeyRef:
                                                    properties:
                                                      key:
                                                        type: string
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                    required:
                                                    - key
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  fieldRef:
                                                    properties:
                                                      apiVersion:
                                                        type: string
                                                      fieldPath:
                                                        type: string
                                                    required:
                                                    - fieldPath
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  resourceFieldRef:
                                                    properties:
                                                      containerName:
                                                        type: string
                                                      divisor:
                                                        anyOf:
                                                        - type: integer
                                                        - type: string
                                                        pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                        x-kubernetes-int-or-string: true
                                                      resource:
                                                        type: string
                                                    required:
                                                    - resource
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  secretKeyRef:
                                                    properties:
                                                      key:
                                                        type: string
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                    required:
                                                    - key
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                type: object
                                            required:
                                            - name
                                            type: object
                                          type: array
                                        envFrom:
                                          items:
                                            properties:
                                              configMapRef:
                                                properties:
                                                  name:
                                                    type: string
                                                  optional:
                                                    type: boolean
                                                type: object
                                                x-kubernetes-map-type: atomic
                                              prefix:
                                                type: string
                                              secretRef:
                                                properties:
                                                  name:
                                                    type: string
                                                  optional:
                                                    type: boolean
                                                type: object
                                                x-kubernetes-map-type: atomic
                                            type: object
                                          type: array
                                        image:
                                          type: string
                                        imagePullPolicy:
                                          type: string
                                        lifecycle:
                                          properties:
                                            postStart:
                                              properties:
                                                exec:
                                                  properties:
                                                    command:
                                                      items:
                                                        type: string
                                                      type: array
                                                  type: object
                                                httpGet:
                                                  properties:
                                                    host:
                                                      type: string
                                                    httpHeaders:
                                                      items:
                                                        properties:
                                                          name:
                                                            type: string
                                                          value:
                                                            type: string
                                                        required:
                                                        - name
                                                        - value
                                                        type: object
                                                      type: array
                                                    path:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                    scheme:
                                                      type: string
                                                  required:
                                                  - port
                                                  type: object
                                                sleep:
                                                  properties:
                                                    seconds:
                                                      format: int64
                                                      type: integer
                                                  required:
                                                  - seconds
                                                  type: object
                                                tcpSocket:
                                                  properties:
                                                    host:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                  required:
                                                  - port
                                                  type: object
                                              type: object
                                            preStop:
                                              properties:
                                                exec:
                                                  properties:
                                                    command:
                                                      items:
                                                        type: string
                                                      type: array
                                                  type: object
                                                httpGet:
                                                  properties:
                                                    host:
                                                      type: string
                                                    httpHeaders:
                                                      items:
                                                        properties:
                                                          name:
                                                            type: string
                                                          value:
                                                            type: string
                                                        required:
                                                        - name
                                                        - value
                                                        type: object
                                                      type: array
                                                    path:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                    scheme:
                                                      type: string
                                                  required:
                                                  - port
                                                  type: object
                                                sleep:
                                                  properties:
                                                    seconds:
                                                      format: int64
                                                      type: integer
                                                  required:
                                                  - seconds
                                                  type: object
                                                tcpSocket:
                                                  properties:
                                                    host:
                                                      type: string
                                                    port:
                                                      anyOf:
                                                      - type: integer
                                                      - type: string
                                                      x-kubernetes-int-or-string: true
                                                  required:
                                                  - port
                                                  type: object
                                              type: object
                                          type: object
                                        livenessProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        name:
                                          type: string
                                        ports:
                                          items:
                                            properties:
                                              containerPort:
                                                format: int32
                                                type: integer
                                              hostIP:
                                                type: string
                                              hostPort:
                                                format: int32
                                                type: integer
                                              name:
                                                type: string
                                              protocol:
                                                default: TCP
                                                type: string
                                            required:
                                            - containerPort
                                            type: object
                                          type: array
                                          x-kubernetes-list-map-keys:
                                          - containerPort
                                          - protocol
                                          x-kubernetes-list-type: map
                                        readinessProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        resizePolicy:
                                          items:
                                            properties:
                                              resourceName:
                                                type: string
                                              restartPolicy:
                                                type: string
                                            required:
                                            - resourceName
                                            - restartPolicy
                                            type: object
                                          type: array
                                          x-kubernetes-list-type: atomic
                                        resources:
                                          properties:
                                            claims:
                                              items:
                                                properties:
                                                  name:
                                                    type: string
                                                required:
                                                - name
                                                type: object
                                              type: array
                                              x-kubernetes-list-map-keys:
                                              - name
                                              x-kubernetes-list-type: map
                                            limits:
                                              additionalProperties:
                                                anyOf:
                                                - type: integer
                                                - type: string
                                                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                x-kubernetes-int-or-string: true
                                              type: object
                                            requests:
                                              additionalProperties:
                                                anyOf:
                                                - type: integer
                                                - type: string
                                                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                x-kubernetes-int-or-string: true
                                              type: object
                                          type: object
                                        restartPolicy:
                                          type: string
                                        securityContext:
                                          properties:
                                            allowPrivilegeEscalation:
                                              type: boolean
                                            capabilities:
                                              properties:
                                                add:
                                                  items:
                                                    type: string
                                                  type: array
                                                drop:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            privileged:
                                              type: boolean
                                            procMount:
                                              type: string
                                            readOnlyRootFilesystem:
                                              type: boolean
                                            runAsGroup:
                                              format: int64
                                              type: integer
                                            runAsNonRoot:
                                              type: boolean
                                            runAsUser:
                                              format: int64
                                              type: integer
                                            seLinuxOptions:
                                              properties:
                                                level:
                                                  type: string
                                                role:
                                                  type: string
                                                type:
                                                  type: string
                                                user:
                                                  type: string
                                              type: object
                                            seccompProfile:
                                              properties:
                                                localhostProfile:
                                                  type: string
                                                type:
                                                  type: string
                                              required:
                                              - type
                                              type: object
                                            windowsOptions:
                                              properties:
                                                gmsaCredentialSpec:
                                                  type: string
                                                gmsaCredentialSpecName:
                                                  type: string
                                                hostProcess:
                                                  type: boolean
                                                runAsUserName:
                                                  type: string
                                              type: object
                                          type: object
                                        startupProbe:
                                          properties:
                                            exec:
                                              properties:
                                                command:
                                                  items:
                                                    type: string
                                                  type: array
                                              type: object
                                            failureThreshold:
                                              format: int32
                                              type: integer
                                            grpc:
                                              properties:
                                                port:
                                                  format: int32
                                                  type: integer
                                                service:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            httpGet:
                                              properties:
                                                host:
                                                  type: string
                                                httpHeaders:
                                                  items:
                                                    properties:
                                                      name:
                                                        type: string
                                                      value:
                                                        type: string
                                                    required:
                                                    - name
                                                    - value
                                                    type: object
                                                  type: array
                                                path:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                                scheme:
                                                  type: string
                                              required:
                                              - port
                                              type: object
                                            initialDelaySeconds:
                                              format: int32
                                              type: integer
                                            periodSeconds:
                                              format: int32
                                              type: integer
                                            successThreshold:
                                              format: int32
                                              type: integer
                                            tcpSocket:
                                              properties:
                                                host:
                                                  type: string
                                                port:
                                                  anyOf:
                                                  - type: integer
                                                  - type: string
                                                  x-kubernetes-int-or-string: true
                                              required:
                                              - port
                                              type: object
                                            terminationGracePeriodSeconds:
                                              format: int64
                                              type: integer
                                            timeoutSeconds:
                                              format: int32
                                              type: integer
                                          type: object
                                        stdin:
                                          type: boolean
                                        stdinOnce:
                                          type: boolean
                                        terminationMessagePath:
                                          type: string
                                        terminationMessagePolicy:
                                          type: string
                                        tty:
                                          type: boolean
                                        volumeDevices:
                                          items:
                                            properties:
                                              devicePath:
                                                type: string
                                              name:
                                                type: string
                                            required:
                                            - devicePath
                                            - name
                                            type: object
                                          type: array
                                        volumeMounts:
                                          items:
                                            properties:
                                              mountPath:
                                                type: string
                                              mountPropagation:
                                                type: string
                                              name:
                                                type: string
                                              readOnly:
                                                type: boolean
                                              subPath:
                                                type: string
                                              subPathExpr:
                                                type: string
                                            required:
                                            - mountPath
                                            - name
                                            type: object
                                          type: array
                                        workingDir:
                                          type: string
                                      required:
                                      - name
                                      type: object
                                    type: array
                                  nodeName:
                                    type: string
                                  nodeSelector:
                                    additionalProperties:
                                      type: string
                                    type: object
                                    x-kubernetes-map-type: atomic
                                  os:
                                    properties:
                                      name:
                                        type: string
                                    required:
                                    - name
                                    type: object
                                  overhead:
                                    additionalProperties:
                                      anyOf:
                                      - type: integer
                                      - type: string
                                      pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                      x-kubernetes-int-or-string: true
                                    type: object
                                  preemptionPolicy:
                                    type: string
                                  priority:
                                    format: int32
                                    type: integer
                                  priorityClassName:
                                    type: string
                                  readinessGates:
                                    items:
                                      properties:
                                        conditionType:
                                          type: string
                                      required:
                                      - conditionType
                                      type: object
                                    type: array
                                  resourceClaims:
                                    items:
                                      properties:
                                        name:
                                          type: string
                                        source:
                                          properties:
                                            resourceClaimName:
                                              type: string
                                            resourceClaimTemplateName:
                                              type: string
                                          type: object
                                      required:
                                      - name
                                      type: object
                                    type: array
                                    x-kubernetes-list-map-keys:
                                    - name
                                    x-kubernetes-list-type: map
                                  restartPolicy:
                                    type: string
                                  runtimeClassName:
                                    type: string
                                  schedulerName:
                                    type: string
                                  schedulingGates:
                                    items:
                                      properties:
                                        name:
                                          type: string
                                      required:
                                      - name
                                      type: object
                                    type: array
                                    x-kubernetes-list-map-keys:
                                    - name
                                    x-kubernetes-list-type: map
                                  securityContext:
                                    properties:
                                      fsGroup:
                                        format: int64
                                        type: integer
                                      fsGroupChangePolicy:
                                        type: string
                                      runAsGroup:
                                        format: int64
                                        type: integer
                                      runAsNonRoot:
                                        type: boolean
                                      runAsUser:
                                        format: int64
                                        type: integer
                                      seLinuxOptions:
                                        properties:
                                          level:
                                            type: string
                                          role:
                                            type: string
                                          type:
                                            type: string
                                          user:
                                            type: string
                                        type: object
                                      seccompProfile:
                                        properties:
                                          localhostProfile:
                                            type: string
                                          type:
                                            type: string
                                        required:
                                        - type
                                        type: object
                                      supplementalGroups:
                                        items:
                                          format: int64
                                          type: integer
                                        type: array
                                      sysctls:
                                        items:
                                          properties:
                                            name:
                                              type: string
                                            value:
                                              type: string
                                          required:
                                          - name
                                          - value
                                          type: object
                                        type: array
                                      windowsOptions:
                                        properties:
                                          gmsaCredentialSpec:
                                            type: string
                                          gmsaCredentialSpecName:
                                            type: string
                                          hostProcess:
                                            type: boolean
                                          runAsUserName:
                                            type: string
                                        type: object
                                    type: object
                                  serviceAccount:
                                    type: string
                                  serviceAccountName:
                                    type: string
                                  setHostnameAsFQDN:
                                    type: boolean
                                  shareProcessNamespace:
                                    type: boolean
                                  subdomain:
                                    type: string
                                  terminationGracePeriodSeconds:
                                    format: int64
                                    type: integer
                                  tolerations:
                                    items:
                                      properties:
                                        effect:
                                          type: string
                                        key:
                                          type: string
                                        operator:
                                          type: string
                                        tolerationSeconds:
                                          format: int64
                                          type: integer
                                        value:
                                          type: string
                                      type: object
                                    type: array
                                  topologySpreadConstraints:
                                    items:
                                      properties:
                                        labelSelector:
                                          properties:
                                            matchExpressions:
                                              items:
                                                properties:
                                                  key:
                                                    type: string
                                                  operator:
                                                    type: string
                                                  values:
                                                    items:
                                                      type: string
                                                    type: array
                                                required:
                                                - key
                                                - operator
                                                type: object
                                              type: array
                                            matchLabels:
                                              additionalProperties:
                                                type: string
                                              type: object
                                          type: object
                                          x-kubernetes-map-type: atomic
                                        matchLabelKeys:
                                          items:
                                            type: string
                                          type: array
                                          x-kubernetes-list-type: atomic
                                        maxSkew:
                                          format: int32
                                          type: integer
                                        minDomains:
                                          format: int32
                                          type: integer
                                        nodeAffinityPolicy:
                                          type: string
                                        nodeTaintsPolicy:
                                          type: string
                                        topologyKey:
                                          type: string
                                        whenUnsatisfiable:
                                          type: string
                                      required:
                                      - maxSkew
                                      - topologyKey
                                      - whenUnsatisfiable
                                      type: object
                                    type: array
                                    x-kubernetes-list-map-keys:
                                    - topologyKey
                                    - whenUnsatisfiable
                                    x-kubernetes-list-type: map
                                  volumes:
                                    items:
                                      properties:
                                        awsElasticBlockStore:
                                          properties:
                                            fsType:
                                              type: string
                                            partition:
                                              format: int32
                                              type: integer
                                            readOnly:
                                              type: boolean
                                            volumeID:
                                              type: string
                                          required:
                                          - volumeID
                                          type: object
                                        azureDisk:
                                          properties:
                                            cachingMode:
                                              type: string
                                            diskName:
                                              type: string
                                            diskURI:
                                              type: string
                                            fsType:
                                              type: string
                                            kind:
                                              type: string
                                            readOnly:
                                              type: boolean
                                          required:
                                          - diskName
                                          - diskURI
                                          type: object
                                        azureFile:
                                          properties:
                                            readOnly:
                                              type: boolean
                                            secretName:
                                              type: string
                                            shareName:
                                              type: string
                                          required:
                                          - secretName
                                          - shareName
                                          type: object
                                        cephfs:
                                          properties:
                                            monitors:
                                              items:
                                                type: string
                                              type: array
                                            path:
                                              type: string
                                            readOnly:
                                              type: boolean
                                            secretFile:
                                              type: string
                                            secretRef:
                                              properties:
                                                name:
                                                  type: string
                                              type: object
                                              x-kubernetes-map-type: atomic
                                            user:
                                              type: string
                                          required:
                                          - monitors
                                          type: object
                                        cinder:
                                          properties:
                                            fsType:
                                              type: string
                                            readOnly:
                                              type: boolean
                                            secretRef:
                                              properties:
                                                name:
                                                  type: string
                                              type: object
                                              x-kubernetes-map-type: atomic
                                            volumeID:
                                              type: string
                                          required:
                                          - volumeID
                                          type: object
                                        configMap:
                                          properties:
                                            defaultMode:
                                              format: int32
                                              type: integer
                                            items:
                                              items:
                                                properties:
                                                  key:
                                                    type: string
                                                  mode:
                                                    format: int32
                                                    type: integer
                                                  path:
                                                    type: string
                                                required:
                                                - key
                                                - path
                                                type: object
                                              type: array
                                            name:
                                              type: string
                                            optional:
                                              type: boolean
                                          type: object
                                          x-kubernetes-map-type: atomic
                                        csi:
                                          properties:
                                            driver:
                                              type: string
                                            fsType:
                                              type: string
                                            nodePublishSecretRef:
                                              properties:
                                                name:
                                                  type: string
                                              type: object
                                              x-kubernetes-map-type: atomic
                                            readOnly:
                                              type: boolean
                                            volumeAttributes:
                                              additionalProperties:
                                                type: string
                                              type: object
                                          required:
                                          - driver
                                          type: object
                                        downwardAPI:
                                          properties:
                                            defaultMode:
                                              format: int32
                                              type: integer
                                            items:
                                              items:
                                                properties:
                                                  fieldRef:
                                                    properties:
                                                      apiVersion:
                                                        type: string
                                                      fieldPath:
                                                        type: string
                                                    required:
                                                    - fieldPath
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  mode:
                                                    format: int32
                                                    type: integer
                                                  path:
                                                    type: string
                                                  resourceFieldRef:
                                                    properties:
                                                      containerName:
                                                        type: string
                                                      divisor:
                                                        anyOf:
                                                        - type: integer
                                                        - type: string
                                                        pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                        x-kubernetes-int-or-string: true
                                                      resource:
                                                        type: string
                                                    required:
                                                    - resource
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                required:
                                                - path
                                                type: object
                                              type: array
                                          type: object
                                        emptyDir:
                                          properties:
                                            medium:
                                              type: string
                                            sizeLimit:
                                              anyOf:
                                              - type: integer
                                              - type: string
                                              pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                              x-kubernetes-int-or-string: true
                                          type: object
                                        ephemeral:
                                          properties:
                                            volumeClaimTemplate:
                                              properties:
                                                metadata:
                                                  type: object
                                                spec:
                                                  properties:
                                                    accessModes:
                                                      items:
                                                        type: string
                                                      type: array
                                                    dataSource:
                                                      properties:
                                                        apiGroup:
                                                          type: string
                                                        kind:
                                                          type: string
                                                        name:
                                                          type: string
                                                      required:
                                                      - kind
                                                      - name
                                                      type: object
                                                      x-kubernetes-map-type: atomic
                                                    dataSourceRef:
                                                      properties:
                                                        apiGroup:
                                                          type: string
                                                        kind:
                                                          type: string
                                                        name:
                                                          type: string
                                                        namespace:
                                                          type: string
                                                      required:
                                                      - kind
                                                      - name
                                                      type: object
                                                    resources:
                                                      properties:
                                                        limits:
                                                          additionalProperties:
                                                            anyOf:
                                                            - type: integer
                                                            - type: string
                                                            pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                            x-kubernetes-int-or-string: true
                                                          type: object
                                                        requests:
                                                          additionalProperties:
                                                            anyOf:
                                                            - type: integer
                                                            - type: string
                                                            pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                            x-kubernetes-int-or-string: true
                                                          type: object
                                                      type: object
                                                    selector:
                                                      properties:
                                                        matchExpressions:
                                                          items:
                                                            properties:
                                                              key:
                                                                type: string
                                                              operator:
                                                                type: string
                                                              values:
                                                                items:
                                                                  type: string
                                                                type: array
                                                            required:
                                                            - key
                                                            - operator
                                                            type: object
                                                          type: array
                                                        matchLabels:
                                                          additionalProperties:
                                                            type: string
                                                          type: object
                                                      type: object
                                                      x-kubernetes-map-type: atomic
                                                    storageClassName:
                                                      type: string
                                                    volumeAttributesClassName:
                                                      type: string
                                                    volumeMode:
                                                      type: string
                                                    volumeName:
                                                      type: string
                                                  type: object
                                              required:
                                              - spec
                                              type: object
                                          type: object
                                        fc:
                                          properties:
                                            fsType:
                                              type: string
                                            lun:
                                              format: int32
                                              type: integer
                                            readOnly:
                                              type: boolean
                                            targetWWNs:
                                              items:
                                                type: string
                                              type: array
                                            wwids:
                                              items:
                                                type: string
                                              type: array
                                          type: object
                                        flexVolume:
                                          properties:
                                            driver:
                                              type: string
                                            fsType:
                                              type: string
                                            options:
                                              additionalProperties:
                                                type: string
                                              type: object
                                            readOnly:
                                              type: boolean
                                            secretRef:
                                              properties:
                                                name:
                                                  type: string
                                              type: object
                                              x-kubernetes-map-type: atomic
                                          required:
                                          - driver
                                          type: object
                                        flocker:
                                          properties:
                                            datasetName:
                                              type: string
                                            datasetUUID:
                                              type: string
                                          type: object
                                        gcePersistentDisk:
                                          properties:
                                            fsType:
                                              type: string
                                            partition:
                                              format: int32
                                              type: integer
                                            pdName:
                                              type: string
                                            readOnly:
                                              type: boolean
                                          required:
                                          - pdName
                                          type: object
                                        gitRepo:
                                          properties:
                                            directory:
                                              type: string
                                            repository:
                                              type: string
                                            revision:
                                              type: string
                                          required:
                                          - repository
                                          type: object
                                        glusterfs:
                                          properties:
                                            endpoints:
                                              type: string
                                            path:
                                              type: string
                                            readOnly:
                                              type: boolean
                                          required:
                                          - endpoints
                                          - path
                                          type: object
                                        hostPath:
                                          properties:
                                            path:
                                              type: string
                                            type:
                                              type: string
                                          required:
                                          - path
                                          type: object
                                        iscsi:
                                          properties:
                                            chapAuthDiscovery:
                                              type: boolean
                                            chapAuthSession:
                                              type: boolean
                                            fsType:
                                              type: string
                                            initiatorName:
                                              type: string
                                            iqn:
                                              type: string
                                            iscsiInterface:
                                              type: string
                                            lun:
                                              format: int32
                                              type: integer
                                            portals:
                                              items:
                                                type: string
                                              type: array
                                            readOnly:
                                              type: boolean
                                            secretRef:
                                              properties:
                                                name:
                                                  type: string
                                              type: object
                                              x-kubernetes-map-type: atomic
                                            targetPortal:
                                              type: string
                                          required:
                                          - iqn
                                          - lun
                                          - targetPortal
                                          type: object
                                        name:
                                          type: string
                                        nfs:
                                          properties:
                                            path:
                                              type: string
                                            readOnly:
                                              type: boolean
                                            server:
                                              type: string
                                          required:
                                          - path
                                          - server
                                          type: object
                                        persistentVolumeClaim:
                                          properties:
                                            claimName:
                                              type: string
                                            readOnly:
                                              type: boolean
                                          required:
                                          - claimName
                                          type: object
                                        photonPersistentDisk:
                                          properties:
                                            fsType:
                                              type: string
                                            pdID:
                                              type: string
                                          required:
                                          - pdID
                                          type: object
                                        portworxVolume:
                                          properties:
                                            fsType:
                                              type: string
                                            readOnly:
                                              type: boolean
                                            volumeID:
                                              type: string
                                          required:
                                          - volumeID
                                          type: object
                                        projected:
                                          properties:
                                            defaultMode:
                                              format: int32
                                              type: integer
                                            sources:
                                              items:
                                                properties:
                                                  clusterTrustBundle:
                                                    properties:
                                                      labelSelector:
                                                        properties:
                                                          matchExpressions:
                                                            items:
                                                              properties:
                                                                key:
                                                                  type: string
                                                                operator:
                                                                  type: string
                                                                values:
                                                                  items:
                                                                    type: string
                                                                  type: array
                                                              required:
                                                              - key
                                                              - operator
                                                              type: object
                                                            type: array
                                                          matchLabels:
                                                            additionalProperties:
                                                              type: string
                                                            type: object
                                                        type: object
                                                        x-kubernetes-map-type: atomic
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                      path:
                                                        type: string
                                                      signerName:
                                                        type: string
                                                    required:
                                                    - path
                                                    type: object
                                                  configMap:
                                                    properties:
                                                      items:
                                                        items:
                                                          properties:
                                                            key:
                                                              type: string
                                                            mode:
                                                              format: int32
                                                              type: integer
                                                            path:
                                                              type: string
                                                          required:
                                                          - key
                                                          - path
                                                          type: object
                                                        type: array
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  downwardAPI:
                                                    properties:
                                                      items:
                                                        items:
                                                          properties:
                                                            fieldRef:
                                                              properties:
                                                                apiVersion:
                                                                  type: string
                                                                fieldPath:
                                                                  type: string
                                                              required:
                                                              - fieldPath
                                                              type: object
                                                              x-kubernetes-map-type: atomic
                                                            mode:
                                                              format: int32
                                                              type: integer
                                                            path:
                                                              type: string
                                                            resourceFieldRef:
                                                              properties:
                                                                containerName:
                                                                  type: string
                                                                divisor:
                                                                  anyOf:
                                                                  - type: integer
                                                                  - type: string
                                                                  pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                                                  x-kubernetes-int-or-string: true
                                                                resource:
                                                                  type: string
                                                              required:
                                                              - resource
                                                              type: object
                                                              x-kubernetes-map-type: atomic
                                                          required:
                                                          - path
                                                          type: object
                                                        type: array
                                                    type: object
                                                  secret:
                                                    properties:
                                                      items:
                                                        items:
                                                          properties:
                                                            key:
                                                              type: string
                                                            mode:
                                                              format: int32
                                                              type: integer
                                                            path:
                                                              type: string
                                                          required:
                                                          - key
                                                          - path
                                                          type: object
                                                        type: array
                                                      name:
                                                        type: string
                                                      optional:
                                                        type: boolean
                                                    type: object
                                                    x-kubernetes-map-type: atomic
                                                  serviceAccountToken:
                                                    properties:
                                                      audience:
                                                        type: string
                                                      expirationSeconds:
                                                        format: int64
                                                        type: integer
                                                      path:
                                                        type: string
                                                    required:
                                                    - path
                                                    type: object
                                                type: object
                                              type: array
                                          type: object
                                        quobyte:
                                          properties:
                                            group:
                                              type: string
                                            readOnly:
                                              type: boolean
                                            registry:
                                              type: string
                                            tenant:
                                              type: string
                                            user:
                                              type: string
                                            volume:
                                              type: string
                                          required:
                                          - registry
                                          - volume
                                          type: object
                                        rbd:
                                          properties:
                                            fsType:
                                              type: string
                                            image:
                                              type: string
                                            keyring:
                                              type: string
                                            monitors:
                                              items:
                                                type: string
                                              type: array
                                            pool:
                                              type: string
                                            readOnly:
                                              type: boolean
                                            secretRef:
                                              properties:
                                                name:
                                                  type: string
                                              type: object
                                              x-kubernetes-map-type: atomic
                                            user:
                                              type: string
                                          required:
                                          - image
                                          - monitors
                                          type: object
                                        scaleIO:
                                          properties:
                                            fsType:
                                              type: string
                                            gateway:
                                              type: string
                                            protectionDomain:
                                              type: string
                                            readOnly:
                                              type: boolean
                                            secretRef:
                                              properties:
                                                name:
                                                  type: string
                                              type: object
                                              x-kubernetes-map-type: atomic
                                            sslEnabled:
                                              type: boolean
                                            storageMode:
                                              type: string
                                            storagePool:
                                              type: string
                                            system:
                                              type: string
                                            volumeName:
                                              type: string
                                          required:
                                          - gateway
                                          - secretRef
                                          - system
                                          type: object
                                        secret:
                                          properties:
                                            defaultMode:
                                              format: int32
                                              type: integer
                                            items:
                                              items:
                                                properties:
                                                  key:
                                                    type: string
                                                  mode:
                                                    format: int32
                                                    type: integer
                                                  path:
                                                    type: string
                                                required:
                                                - key
                                                - path
                                                type: object
                                              type: array
                                            optional:
                                              type: boolean
                                            secretName:
                                              type: string
                                          type: object
                                        storageos:
                                          properties:
                                            fsType:
                                              type: string
                                            readOnly:
                                              type: boolean
                                            secretRef:
                                              properties:
                                                name:
                                                  type: string
                                              type: object
                                              x-kubernetes-map-type: atomic
                                            volumeName:
                                              type: string
                                            volumeNamespace:
                                              type: string
                                          type: object
                                        vsphereVolume:
                                          properties:
                                            fsType:
                                              type: string
                                            storagePolicyID:
                                              type: string
                                            storagePolicyName:
                                              type: string
                                            volumePath:
                                              type: string
                                          required:
                                          - volumePath
                                          type: object
                                      required:
                                      - name
                                      type: object
                                    type: array
                                required:
                                - containers
                                type: object
                            type: object
                          updateStrategy:
                            properties:
                              rollingUpdate:
                                properties:
                                  maxUnavailable:
                                    anyOf:
                                    - type: integer
                                    - type: string
                                    x-kubernetes-int-or-string: true
                                  partition:
                                    format: int32
                                    type: integer
                                type: object
                              type:
                                type: string
                            type: object
                          volumeClaimTemplates:
                            items:
                              properties:
                                apiVersion:
                                  type: string
                                kind:
                                  type: string
                                metadata:
                                  properties:
                                    annotations:
                                      additionalProperties:
                                        type: string
                                      type: object
                                    labels:
                                      additionalProperties:
                                        type: string
                                      type: object
                                    name:
                                      type: string
                                    namespace:
                                      type: string
                                  type: object
                                spec:
                                  properties:
                                    accessModes:
                                      items:
                                        type: string
                                      type: array
                                    dataSource:
                                      properties:
                                        apiGroup:
                                          type: string
                                        kind:
                                          type: string
                                        name:
                                          type: string
                                      required:
                                      - kind
                                      - name
                                      type: object
                                      x-kubernetes-map-type: atomic
                                    dataSourceRef:
                                      properties:
                                        apiGroup:
                                          type: string
                                        kind:
                                          type: string
                                        name:
                                          type: string
                                        namespace:
                                          type: string
                                      required:
                                      - kind
                                      - name
                                      type: object
                                    resources:
                                      properties:
                                        limits:
                                          additionalProperties:
                                            anyOf:
                                            - type: integer
                                            - type: string
                                            pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                            x-kubernetes-int-or-string: true
                                          type: object
                                        requests:
                                          additionalProperties:
                                            anyOf:
                                            - type: integer
                                            - type: string
                                            pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                            x-kubernetes-int-or-string: true
                                          type: object
                                      type: object
                                    selector:
                                      properties:
                                        matchExpressions:
                                          items:
                                            properties:
                                              key:
                                                type: string
                                              operator:
                                                type: string
                                              values:
                                                items:
                                                  type: string
                                                type: array
                                            required:
                                            - key
                                            - operator
                                            type: object
                                          type: array
                                        matchLabels:
                                          additionalProperties:
                                            type: string
                                          type: object
                                      type: object
                                      x-kubernetes-map-type: atomic
                                    storageClassName:
                                      type: string
                                    volumeAttributesClassName:
                                      type: string
                                    volumeMode:
                                      type: string
                                    volumeName:
                                      type: string
                                  type: object
                              type: object
                            type: array
                        type: object
                    type: object
                type: object
              persistence:
                default:
                  storage: 10Gi
                description: The desired persistent storage configuration for each
                  Pod in the cluster.
                properties:
                  storage:
                    anyOf:
                    - type: integer
                    - type: string
                    default: 10Gi
                    description: The requested size of the persistent volume attached
                      to each Pod in the RabbitmqCluster. The format of this field
                      matches that defined by kubernetes/apimachinery. See https://pkg.go.dev/k8s.io/apimachinery/pkg/api/resource#Quantity
                      for more info on the format of this field.
                    pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                    x-kubernetes-int-or-string: true
                  storageClassName:
                    description: The name of the StorageClass to claim a PersistentVolume
                      from.
                    type: string
                type: object
              rabbitmq:
                description: Configuration options for RabbitMQ Pods created in the
                  cluster.
                properties:
                  additionalConfig:
                    description: Modify to add to the rabbitmq.conf file in addition
                      to default configurations set by the operator. Modifying this
                      property on an existing RabbitmqCluster will trigger a StatefulSet
                      rolling restart and will cause rabbitmq downtime. For more information
                      on this config, see https://www.rabbitmq.com/configure.html#config-file
                    maxLength: 2000
                    type: string
                  additionalPlugins:
                    description: 'List of plugins to enable in addition to essential
                      plugins: rabbitmq_management, rabbitmq_prometheus, and rabbitmq_peer_discovery_k8s.'
                    items:
                      description: A Plugin to enable on the RabbitmqCluster.
                      maxLength: 100
                      pattern: ^\w+$
                      type: string
                    maxItems: 100
                    type: array
                  advancedConfig:
                    description: Specify any rabbitmq advanced.config configurations
                      to apply to the cluster. For more information on advanced config,
                      see https://www.rabbitmq.com/configure.html#advanced-config-file
                    maxLength: 100000
                    type: string
                  envConfig:
                    description: Modify to add to the rabbitmq-env.conf file. Modifying
                      this property on an existing RabbitmqCluster will trigger a
                      StatefulSet rolling restart and will cause rabbitmq downtime.
                      For more information on env config, see https://www.rabbitmq.com/man/rabbitmq-env.conf.5.html
                    maxLength: 100000
                    type: string
                  erlangInetConfig:
                    description: 'Erlang Inet configuration to apply to the Erlang
                      VM running rabbit. See also: https://www.erlang.org/doc/apps/erts/inet_cfg.html'
                    maxLength: 2000
                    type: string
                type: object
              replicas:
                default: 1
                description: Replicas is the number of nodes in the RabbitMQ cluster.
                  Each node is deployed as a Replica in a StatefulSet. Only 1, 3,
                  5 replicas clusters are tested. This value should be an odd number
                  to ensure the resultant cluster can establish exactly one quorum
                  of nodes in the event of a fragmenting network partition.
                format: int32
                minimum: 0
                type: integer
              resources:
                default:
                  limits:
                    cpu: 2000m
                    memory: 2Gi
                  requests:
                    cpu: 1000m
                    memory: 2Gi
                description: The desired compute resource requirements of Pods in
                  the cluster.
                properties:
                  claims:
                    description: "Claims lists the names of resources, defined in
                      spec.resourceClaims, that are used by this container. \n This
                      is an alpha field and requires enabling the DynamicResourceAllocation
                      feature gate. \n This field is immutable. It can only be set
                      for containers."
                    items:
                      description: ResourceClaim references one entry in PodSpec.ResourceClaims.
                      properties:
                        name:
                          description: Name must match the name of one entry in pod.spec.resourceClaims
                            of the Pod where this field is used. It makes that resource
                            available inside a container.
                          type: string
                      required:
                      - name
                      type: object
                    type: array
                    x-kubernetes-list-map-keys:
                    - name
                    x-kubernetes-list-type: map
                  limits:
                    additionalProperties:
                      anyOf:
                      - type: integer
                      - type: string
                      pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                      x-kubernetes-int-or-string: true
                    description: 'Limits describes the maximum amount of compute resources
                      allowed. More info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/'
                    type: object
                  requests:
                    additionalProperties:
                      anyOf:
                      - type: integer
                      - type: string
                      pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                      x-kubernetes-int-or-string: true
                    description: 'Requests describes the minimum amount of compute
                      resources required. If Requests is omitted for a container,
                      it defaults to Limits if that is explicitly specified, otherwise
                      to an implementation-defined value. Requests cannot exceed Limits.
                      More info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/'
                    type: object
                type: object
              secretBackend:
                description: Secret backend configuration for the RabbitmqCluster.
                  Enables to fetch default user credentials and certificates from
                  K8s external secret stores.
                properties:
                  externalSecret:
                    description: LocalObjectReference contains enough information
                      to let you locate the referenced object inside the same namespace.
                    properties:
                      name:
                        description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names
                          TODO: Add other useful fields. apiVersion, kind, uid?'
                        type: string
                    type: object
                    x-kubernetes-map-type: atomic
                  vault:
                    description: VaultSpec will add Vault annotations (see https://www.vaultproject.io/docs/platform/k8s/injector/annotations)
                      to RabbitMQ Pods. It requires a Vault Agent Sidecar Injector
                      (https://www.vaultproject.io/docs/platform/k8s/injector) to
                      be installed in the K8s cluster. The injector is a K8s Mutation
                      Webhook Controller that alters RabbitMQ Pod specifications (based
                      on the added Vault annotations) to include Vault Agent containers
                      that render Vault secrets to the volume.
                    properties:
                      annotations:
                        additionalProperties:
                          type: string
                        description: Vault annotations that override the Vault annotations
                          set by the cluster-operator. For a list of valid Vault annotations,
                          see https://www.vaultproject.io/docs/platform/k8s/injector/annotations
                        type: object
                      defaultUserPath:
                        description: Path in Vault to access a KV (Key-Value) secret
                          with the fields username and password for the default user.
                          For example "secret/data/rabbitmq/config".
                        type: string
                      defaultUserUpdaterImage:
                        description: Sidecar container that updates the default user's
                          password in RabbitMQ when it changes in Vault. Additionally,
                          it updates /var/lib/rabbitmq/.rabbitmqadmin.conf (used by
                          rabbitmqadmin CLI). Set to empty string to disable the sidecar
                          container.
                        type: string
                      role:
                        description: Role in Vault. If vault.defaultUserPath is set,
                          this role must have capability to read the pre-created default
                          user credential in Vault. If vault.tls is set, this role
                          must have capability to create and update certificates in
                          the Vault PKI engine for the domains "<namespace>" and "<namespace>.svc".
                        type: string
                      tls:
                        properties:
                          altNames:
                            description: 'Specifies the requested Subject Alternative
                              Names (SANs), in a comma-delimited list. These will
                              be appended to the SANs added by the cluster-operator.
                              The cluster-operator will add SANs: "<RabbitmqCluster
                              name>-server-<index>.<RabbitmqCluster name>-nodes.<namespace>"
                              for each pod, e.g. "myrabbit-server-0.myrabbit-nodes.default".'
                            type: string
                          commonName:
                            description: Specifies the requested certificate Common
                              Name (CN). Defaults to <serviceName>.<namespace>.svc
                              if not provided.
                            type: string
                          ipSans:
                            description: Specifies the requested IP Subject Alternative
                              Names, in a comma-delimited list.
                            type: string
                          pkiIssuerPath:
                            description: Path in Vault PKI engine. For example "pki/issue/hashicorp-com".
                              required
                            type: string
                        type: object
                    type: object
                type: object
              service:
                default:
                  type: ClusterIP
                description: The desired state of the Kubernetes Service to create
                  for the cluster.
                properties:
                  annotations:
                    additionalProperties:
                      type: string
                    description: Annotations to add to the Service.
                    type: object
                  ipFamilyPolicy:
                    description: 'IPFamilyPolicy represents the dual-stack-ness requested
                      or required by a Service See also: https://pkg.go.dev/k8s.io/api/core/v1#IPFamilyPolicy'
                    enum:
                    - SingleStack
                    - PreferDualStack
                    - RequireDualStack
                    type: string
                  type:
                    default: ClusterIP
                    description: 'Type of Service to create for the cluster. Must
                      be one of: ClusterIP, LoadBalancer, NodePort. For more info
                      see https://pkg.go.dev/k8s.io/api/core/v1#ServiceType'
                    enum:
                    - ClusterIP
                    - LoadBalancer
                    - NodePort
                    type: string
                type: object
              skipPostDeploySteps:
                description: If unset, or set to false, the cluster will run `rabbitmq-queues
                  rebalance all` whenever the cluster is updated. Set to true to prevent
                  the operator rebalancing queue leaders after a cluster update. Has
                  no effect if the cluster only consists of one node. For more information,
                  see https://www.rabbitmq.com/rabbitmq-queues.8.html#rebalance
                type: boolean
              terminationGracePeriodSeconds:
                default: 604800
                description: 'TerminationGracePeriodSeconds is the timeout that each
                  rabbitmqcluster pod will have to terminate gracefully. It defaults
                  to 604800 seconds ( a week long) to ensure that the container preStop
                  lifecycle hook can finish running. For more information, see: https://github.com/rabbitmq/cluster-operator/blob/main/docs/design/20200520-graceful-pod-termination.md'
                format: int64
                minimum: 0
                type: integer
              tls:
                description: TLS-related configuration for the RabbitMQ cluster.
                properties:
                  caSecretName:
                    description: Name of a Secret in the same Namespace as the RabbitmqCluster,
                      containing the Certificate Authority's public certificate for
                      TLS. The Secret must store this as ca.crt. This Secret can be
                      created by running `kubectl create secret generic ca-secret
                      --from-file=ca.crt=path/to/ca.cert` Used for mTLS, and TLS for
                      rabbitmq_web_stomp and rabbitmq_web_mqtt.
                    type: string
                  disableNonTLSListeners:
                    description: 'When set to true, the RabbitmqCluster disables non-TLS
                      listeners for RabbitMQ, management plugin and for any enabled
                      plugins in the following list: stomp, mqtt, web_stomp, web_mqtt.
                      Only TLS-enabled clients will be able to connect.'
                    type: boolean
                  secretName:
                    description: Name of a Secret in the same Namespace as the RabbitmqCluster,
                      containing the server's private key & public certificate for
                      TLS. The Secret must store these as tls.key and tls.crt, respectively.
                      This Secret can be created by running `kubectl create secret
                      tls tls-secret --cert=path/to/tls.cert --key=path/to/tls.key`
                    type: string
                type: object
              tolerations:
                description: Tolerations is the list of Toleration resources attached
                  to each Pod in the RabbitmqCluster.
                items:
                  description: The pod this Toleration is attached to tolerates any
                    taint that matches the triple <key,value,effect> using the matching
                    operator <operator>.
                  properties:
                    effect:
                      description: Effect indicates the taint effect to match. Empty
                        means match all taint effects. When specified, allowed values
                        are NoSchedule, PreferNoSchedule and NoExecute.
                      type: string
                    key:
                      description: Key is the taint key that the toleration applies
                        to. Empty means match all taint keys. If the key is empty,
                        operator must be Exists; this combination means to match all
                        values and all keys.
                      type: string
                    operator:
                      description: Operator represents a key's relationship to the
                        value. Valid operators are Exists and Equal. Defaults to Equal.
                        Exists is equivalent to wildcard for value, so that a pod
                        can tolerate all taints of a particular category.
                      type: string
                    tolerationSeconds:
                      description: TolerationSeconds represents the period of time
                        the toleration (which must be of effect NoExecute, otherwise
                        this field is ignored) tolerates the taint. By default, it
                        is not set, which means tolerate the taint forever (do not
                        evict). Zero and negative values will be treated as 0 (evict
                        immediately) by the system.
                      format: int64
                      type: integer
                    value:
                      description: Value is the taint value the toleration matches
                        to. If the operator is Exists, the value should be empty,
                        otherwise just a regular string.
                      type: string
                  type: object
                type: array
            type: object
          status:
            description: Status presents the observed state of RabbitmqCluster
            properties:
              binding:
                description: 'Binding exposes a secret containing the binding information
                  for this RabbitmqCluster. It implements the service binding Provisioned
                  Service duck type. See: https://github.com/servicebinding/spec#provisioned-service'
                properties:
                  name:
                    description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names
                      TODO: Add other useful fields. apiVersion, kind, uid?'
                    type: string
                type: object
                x-kubernetes-map-type: atomic
              conditions:
                description: Set of Conditions describing the current state of the
                  RabbitmqCluster
                items:
                  properties:
                    lastTransitionTime:
                      description: The last time this Condition type changed.
                      format: date-time
                      type: string
                    message:
                      description: Full text reason for current status of the condition.
                      type: string
                    reason:
                      description: One word, camel-case reason for current status
                        of the condition.
                      type: string
                    status:
                      description: True, False, or Unknown
                      type: string
                    type:
                      description: Type indicates the scope of RabbitmqCluster status
                        addressed by the condition.
                      type: string
                  required:
                  - status
                  - type
                  type: object
                type: array
              defaultUser:
                description: Identifying information on internal resources
                properties:
                  secretReference:
                    description: Reference to the Kubernetes Secret containing the
                      credentials of the default user.
                    properties:
                      keys:
                        additionalProperties:
                          type: string
                        description: Key-value pairs in the Secret corresponding to
                          `username`, `password`, `host`, and `port`
                        type: object
                      name:
                        description: Name of the Secret containing the default user
                          credentials
                        type: string
                      namespace:
                        description: Namespace of the Secret containing the default
                          user credentials
                        type: string
                    required:
                    - keys
                    - name
                    - namespace
                    type: object
                  serviceReference:
                    description: Reference to the Kubernetes Service serving the cluster.
                    properties:
                      name:
                        description: Name of the Service serving the cluster
                        type: string
                      namespace:
                        description: Namespace of the Service serving the cluster
                        type: string
                    required:
                    - name
                    - namespace
                    type: object
                type: object
              observedGeneration:
                description: observedGeneration is the most recent successful generation
                  observed for this RabbitmqCluster. It corresponds to the RabbitmqCluster's
                  generation, which is updated on mutation by the API Server.
                format: int64
                type: integer
            required:
            - conditions
            type: object
        type: object
    served: true
    storage: true
    subresources:
      status: {}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rabbitmq-cluster-operator
  namespace: rabbitmq-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  labels:
    app.kubernetes.io/component: rabbitmq-operator
    app.kubernetes.io/name: rabbitmq-cluster-operator
    app.kubernetes.io/part-of: rabbitmq
  name: rabbitmq-cluster-leader-election-role
  namespace: rabbitmq-system
rules:
- apiGroups:
  - coordination.k8s.io
  resources:
  - leases
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    app.kubernetes.io/component: rabbitmq-operator
    app.kubernetes.io/name: rabbitmq-cluster-operator
    app.kubernetes.io/part-of: rabbitmq
  name: rabbitmq-cluster-operator-role
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - create
  - get
  - list
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - endpoints
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
  - get
  - patch
- apiGroups:
  - ""
  resources:
  - persistentvolumeclaims
  verbs:
  - create
  - get
  - list
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - pods/exec
  verbs:
  - create
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - create
  - get
  - list
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - serviceaccounts
  verbs:
  - create
  - get
  - list
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - create
  - get
  - list
  - update
  - watch
- apiGroups:
  - apps
  resources:
  - statefulsets
  verbs:
  - create
  - delete
  - get
  - list
  - update
  - watch
- apiGroups:
  - rabbitmq.com
  resources:
  - rabbitmqclusters
  verbs:
  - create
  - get
  - list
  - update
  - watch
- apiGroups:
  - rabbitmq.com
  resources:
  - rabbitmqclusters/finalizers
  verbs:
  - update
- apiGroups:
  - rabbitmq.com
  resources:
  - rabbitmqclusters/status
  verbs:
  - get
  - update
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - rolebindings
  verbs:
  - create
  - get
  - list
  - update
  - watch
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - roles
  verbs:
  - create
  - get
  - list
  - update
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    app.kubernetes.io/component: rabbitmq-operator
    app.kubernetes.io/name: rabbitmq-cluster-operator
    app.kubernetes.io/part-of: rabbitmq
    servicebinding.io/controller: "true"
  name: rabbitmq-cluster-service-binding-role
rules:
- apiGroups:
  - rabbitmq.com
  resources:
  - rabbitmqclusters
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    app.kubernetes.io/component: rabbitmq-operator
    app.kubernetes.io/name: rabbitmq-cluster-operator
    app.kubernetes.io/part-of: rabbitmq
  name: rabbitmq-cluster-leader-election-rolebinding
  namespace: rabbitmq-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: rabbitmq-cluster-leader-election-role
subjects:
- kind: ServiceAccount
  name: rabbitmq-cluster-operator
  namespace: rabbitmq-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    app.kubernetes.io/component: rabbitmq-operator
    app.kubernetes.io/name: rabbitmq-cluster-operator
    app.kubernetes.io/part-of: rabbitmq
  name: rabbitmq-cluster-operator-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: rabbitmq-cluster-operator-role
subjects:
- kind: ServiceAccount
  name: rabbitmq-cluster-operator
  namespace: rabbitmq-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/component: rabbitmq-operator
    app.kubernetes.io/name: rabbitmq-cluster-operator
    app.kubernetes.io/part-of: rabbitmq
  name: rabbitmq-cluster-operator
  namespace: rabbitmq-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: rabbitmq-cluster-operator
  template:
    metadata:
      labels:
        app.kubernetes.io/component: rabbitmq-operator
        app.kubernetes.io/name: rabbitmq-cluster-operator
        app.kubernetes.io/part-of: rabbitmq
    spec:
      containers:
      - command:
        - /manager
        env:
        - name: OPERATOR_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        image: rabbitmqoperator/cluster-operator:2.7.0
        name: operator
        ports:
        - containerPort: 9782
          name: metrics
          protocol: TCP
        resources:
          limits:
            cpu: 200m
            memory: 500Mi
          requests:
            cpu: 200m
            memory: 500Mi
      serviceAccountName: rabbitmq-cluster-operator
      terminationGracePeriodSeconds: 10

```

## File: `deploy-yml/not-needed-created-with-helm-rabbitmq-cluster.yaml`
- **File Size:** 319 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** create ingress rules with terraform

```
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: rabbitmq-cluster
  namespace: rabbitmq-system
spec:
  replicas: 2
  persistence:
    storageClassName: do-block-storage
    storage: 10Gi
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 1000m
      memory: 2Gi
```

## File: `deploy-yml/not-needed-created-with-terraform-configmap.yaml`
- **File Size:** 732 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** create ingress rules with terraform

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: rmq-config
data:
  RMQ_HOST: "rabbitmq-cluster"
  RMQ_PORT: "5672"
  RMQ_VHOST: "ufl"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fanclash-config
data:
  AMQP_MATCH_EVENTS_EXCHANGE: "match_event"
  AMQP_GAMES_EXCHANGE: "games"
  AMQP_SYSTEM_EXCHANGE: "system"
  STATSD_HOST: "telegraf.monitoring.svc"
  GCE_PLAYER_IMAGES_BUCKET: "ufl-player-images"
  GCE_TEAM_CRESTS_BUCKET: "ufl-team-crests"
  GCE_USER_AVATAR_BUCKET: "fanclash-user-avatars"
  GCE_OPTA_FEED_BUCKET: "ufl-opta-feeds"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mobile-api-config
data:
  DJANGO_SETTINGS_MODULE: "mobile_api.settings.staging"
  REVENUE_CAT_API_KEY: "APUPZvmsHAwSCySdKizykqvGJOLdFLcX"
```

## File: `deploy-yml/not-needed-created-with-terraform-ingress.yaml`
- **File Size:** 2171 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** create ingress rules with terraform

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    kubernetes.io/tls-acme: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
  name: fanclash-ingress
  namespace: fanclash-dev
spec:
  ingressClassName: nginx
  rules:
  - host: laliga.gamebuild.co
    http:
        paths:
        - pathType: Prefix
          path: "/"
          backend:
            service:
              name: mobile-api
              port:
                number: 80
        - pathType: Prefix
          path: "/api/revenuecat/sync/"
          backend:
            service:
              name: mobile-api
              port:
                number: 80
        - pathType: Prefix
          path: "/api/users/profile/avatar/"
          backend:
            service:
              name: mobile-api
              port:
                number: 80
        - pathType: Prefix
          path: "/api/users/profile/avatar/"
          backend:
            service:
              name: mobile-api
              port:
                number: 80
        - pathType: Prefix
          path: "/api"
          backend:
            service:
              name: fanclash-api
              port:
                number: 80
        - pathType: Prefix
          path: "/api/ws"
          backend:
            service:
              name: fanclash-api-ws
              port:
                number: 80

  tls:
  - secretName: letsencrypt-prod
    hosts:
    - laliga.gamebuild.co
        # paths:
        # - path: /
        #   backend:
        #     serviceName: mobile-api-staging
        #     servicePort: 80

        # - path: /api
        #   backend:
        #     serviceName: fanclash-api-staging
        #     servicePort: 80

        # - path: /api/revenuecat/sync/
        #   backend:
        #     serviceName: mobile-api-production
        #     servicePort: 80

        # - path: /api/users/profile/avatar/
        #   backend:
        #     serviceName: mobile-api-staging
        #     servicePort: 80

        # - path: /api/ws
        #   backend:
        #     serviceName: fanclash-api-ws-staging
        #     servicePort: 80
```

## File: `deploy-yml/not-needed-created-with-terraform-secret.yaml`
- **File Size:** 7009 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** create ingress rules with terraform

```
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
type: Opaque
data:
  DATABASE_PASSWORD: QVZOU190Rmx4V3pKU0w0THUyeUQ5aTBQ
  DATABASE_USER: ZmFuY2xhc2g=
  DATABASE_HOST: ZmFuY2xhc2gtZG8tdXNlci0xNTYzNDM3OC0wLmMuZGIub25kaWdpdGFsb2NlYW4uY29t
  DATABASE_NAME: ZmFuY2xhc2g=
  DATABASE_PORT: MjUwNjA=
  DATABASE_SSLMODE: cmVxdWlyZQ==
---
apiVersion: v1
kind: Secret
metadata:
  name: fcm-creds
type: Opaque
data:
  FCM_CREDENTIALS: eyJ0eXBlIjogInNlcnZpY2VfYWNjb3VudCIsInByb2plY3RfaWQiOiAiZmFuY2xhc2gtcnRnLXN0YWciLCJwcml2YXRlX2tleV9pZCI6ICJiNjRkYWFlODJhNzI0ZDdkNmJiZDU3NmIxNTNjMmEyZjBhNzNkY2UwIiwicHJpdmF0ZV9rZXkiOiAiLS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tXG5NSUlFdlFJQkFEQU5CZ2txaGtpRzl3MEJBUUVGQUFTQ0JLY3dnZ1NqQWdFQUFvSUJBUUNNWFJPajNhV0NrQ2E5XG5RS1RXRzJFR0EvMGNRcDdqcnRKU2ZwdkFoUTFSQ0NlZU5WSnhvT1A0L3ViV1F0dTFaUFdYa2cycE45UGlnVDBaXG5PQlJUSVY2S20yZ0pTeWpNNnJTRll2dFk1NEVQTFhpbmNIYWJud1htZ3FzdTkwMFU4c0JWTmF4WlBTWStrcTlvXG5EQ1hRMk1HTzRieHdUM0s4RSs1a2srUzdNekkyMithVWZGUmpCQ3NBeTVFNHNRcDlJaEszK240THlwTGdoZS82XG5NS0tWbFBNeUJoOGhXUnBhN1o2RFArbWkwUGEzTUFpbXJXRHFtKy94SytJR2FKZnRwaytnc1NvQkxSU3FUUnNnXG5VQU0wWUh0MkFKYTU5S0xXeFYrczZnYUN0eTJOa1NyalNWcC9xZHh6ai9SS09jZDlSUjMyVW9yMy9TMmV5QnpXXG5GQnVRMWpvWkFnTUJBQUVDZ2dFQUFiZnQzQ1dFQ0ZpOTFOTlZ5UUlybm9UZFk5c3ZVaE12ZmFZSUVGdWpuK0JHXG51RmRlTVBWYmRscHZyNVhLUXlFODI4VlFYbVJmL21TKytHSFp3V2h0R3lhQ2M3Y2U5dnNBV1p6NlFFcWV5TE1vXG5NSHhRQU9xM2JiUHdsbDhQakp1VzU0Y2dzcS9qZlZBSnNpMENIdGwvQ2VmbXBZZVYyaGpSYU9LM1BsWGNNMkJRXG42UTBoWUN4QWFDWVhKWDg5UHhvc0ZGOWJFRk8wQ0hsOG9aYkY1STJtUEhmRWNWdHEzL0R5eE9QT29NMC91ZnpuXG5PUS9MbU9PTURrcHJWVlZDaVBxOVNCeFlCYWZCWnNrK3YzZ2hsMVNUbFEwcWdvSGliemFnTVB5TEV6RjdXbE8zXG5JU0U2R0tJaG13MzlzbVJvSFBGaWFuZk9UdnNobGhrWXo1bEozQnFiZ1FLQmdRRENFS0N3c1RPWnpCUGNza1N1XG5GM0JrMS9MR0JDZkdNRHAvdkV2NnVkMTdXNk5vNWE3K0FKQXpVb1oyakx2Wllna28zR3Z0cEdHMG5ub21zaXNTXG5wYXJ2QUZoOGxzTEtEaU0waWJ6K0t6WTZ2Y1FleEllM0JQTHJBOFlQd3ZUQmFnYWRES2xoVzRoblVJZWNrVWZrXG4vb0RWckU1NVpPV0EzTk03MUtQNW84cWt1d0tCZ1FDNUtQazE4d3RmTmd4QlJ2QTJXekoxenNUSGNoam1mTGEyXG5vbFpiYyt2OWZ1cU5JVDFHUzNBSE0xcGNEOVhML2g3czBzc2VjbzI4UDgwWjhWdFhWUE8xTFNnN3R0N0dpYVFxXG5KRUxrNEhBaFNaUzNCZVA0Zzk3dlpWeHR3ZjRRcEpoRkEycEp3TC9ZV2MxbGwyQXA2VFVzSGhySzkxQUdqVE51XG5UVmRmS21RWk93S0JnUUNnb3ZMZ1QwM1BPTVlZSU5nSTR3Mzk2MkxoMWY2MlpxV0ZwbStlRXN2cW1HZ2pKRHc5XG50R21va2Q4THNtS3NCaUplMkZYZVYvc29ieVhkY2cyRldleXIrVFZGcStXQkswS284bnFtU1U2U1FSSmVCWC94XG5WdjljMmJyUXdTZW9FZ04zYkV1b2N3UHR3UkwvM3FJTVF6NlJvQmMxRlBlRU8wWCtlSDFpM3RtV2tRS0JnSFVXXG5mdmxwdDBBL0ttTEJIRGdUVllaLytabnlBZU1HN0hmemtrNkVzSy85NlE3VC9TNk5sOHRGNHhjaWdGMWVWbW9HXG5KcUliYUp1cGNPYTk1TGdHSlpMbGVuTEFnb0hrR21iM3hVRjgyQXVFdjBFNXZWNnk3WEJQbGJKbW9XWWUzNWVNXG53RkxoUzYvaG9leGpYRkZFZ3ZaaUZ5bFFXVSs3VE5Hc29OcXlNTmh2QW9HQVVzNFpBVWxBZW5iQWViNms3N0VNXG5PWURKYVY4dFUyUzJQNndMK3NEdU1KdGNOWmZ2ZUFDOUp1QU1WcmlrZUNtbGNjaE5kWklESE85VWd4c0xDYXF5XG41RENsVkF3Q3F4eUdrUTJzc0l5VEdic1BieGhiM01ybXhINE5keUJLZDZtMXhMdUtSdXRRWSt1bUxSMm9RYWRNXG5LU0NZYml5eHB5V1lKNVUxcVZQTnNmZz1cbi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS1cbiIsImNsaWVudF9lbWFpbCI6ICJmaXJlYmFzZS1hZG1pbnNkay1qaGluOEBmYW5jbGFzaC1ydGctc3RhZy5pYW0uZ3NlcnZpY2VhY2NvdW50LmNvbSIsImNsaWVudF9pZCI6ICIxMTI3MDcxNDk2NjYxNTkwMTEyNTMiLCJhdXRoX3VyaSI6ICJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20vby9vYXV0aDIvYXV0aCIsInRva2VuX3VyaSI6ICJodHRwczovL29hdXRoMi5nb29nbGVhcGlzLmNvbS90b2tlbiIsImF1dGhfcHJvdmlkZXJfeDUwOV9jZXJ0X3VybCI6ICJodHRwczovL3d3dy5nb29nbGVhcGlzLmNvbS9vYXV0aDIvdjEvY2VydHMiLCJjbGllbnRfeDUwOV9jZXJ0X3VybCI6ICJodHRwczovL3d3dy5nb29nbGVhcGlzLmNvbS9yb2JvdC92MS9tZXRhZGF0YS94NTA5L2ZpcmViYXNlLWFkbWluc2RrLWpoaW44JTQwZmFuY2xhc2gtcnRnLXN0YWcuaWFtLmdzZXJ2aWNlYWNjb3VudC5jb20iLCJ1bml2ZXJzZV9kb21haW4iOiAiZ29vZ2xlYXBpcy5jb20ifQ==
---
apiVersion: v1
kind: Secret
metadata:
  name: ortec-creds
type: Opaque
data:
  ORTEC_USERNAME: aW5wbGF5bGFicw==
  ORTEC_PASSWORD: VTZYWjM3REw=
---
apiVersion: v1
kind: Secret
metadata:
  name: opta-feed-creds
type: Opaque
data:
  credentials: ewogICJ0eXBlIjogInNlcnZpY2VfYWNjb3VudCIsCiAgInByb2plY3RfaWQiOiAidWZsLTIwIiwKICAicHJpdmF0ZV9rZXlfaWQiOiAiODQwYTg3NWEwOGVmZDM3YTFlMjdlMDFmMTVjNjhiM2VjMzk0N2QxOSIsCiAgInByaXZhdGVfa2V5IjogIi0tLS0tQkVHSU4gUFJJVkFURSBLRVktLS0tLVxuTUlJRXZnSUJBREFOQmdrcWhraUc5dzBCQVFFRkFBU0NCS2d3Z2dTa0FnRUFBb0lCQVFDbzJhbzdhenVDdzMzdVxuUjA0clVjU1BKcUVEV0x6Z1lZVUtoS2JDcGlPR21nNS81aTEydjFyaEJIK0M2eE1ndnB0Y1BIVXNrMjY5Lys5Wlxuc3NEdThDejd5RlVLYy9OcTZqbWxkWlBxemFFV3FVeG5NVTluVS9QVnVKaVUwejN2S005dmhrZXRqN2dPQTZxalxuWjdKcCtnS2ZQYkxDTGhySi9Ua2w5NmJDaXBLVWRqRmVHVXR1VjNmamoxZ0t6S3AxUy9ZNVRGQ2gzallFWDdheFxuT3lPV05VcXNsd2VUQlJHQ1FXK0Q1ZjRpMUJMVk1QMnQ3UWhhenplTmtwOVhVbWVkRnB3Q2ZBTHg3SjR1LzRpT1xuRlJkLzlNTDgxR2xqdFk5QzE0UkNaRzBlN2dQNkhxdkxqelVOdGswZWZZOHJXeGhHbDU0SStWS2tqNTA1bXl0S1xuRUFMTVF6ZlJBZ01CQUFFQ2dnRUFCUitsdjJ2VTZ5RGlLZ3JXaW1YNWRadm5JdUl4eVFxWExqeUc1WktEc3NxVlxuOUxlWUJaUnZrNGhwYU1ydFVsUmhBOVFwMGhKMGpTWVRyZXNlQTZJY3hmOGhrQ2I0bEo2Z09vUnVML1Vtd0RpZVxuN1pBSGZYYUVzdnJlVm1zYWpxNmZBaDZzVk0zdStJTTZvdjY3TnBBSmt2OXlTZHQ2OWZUTnpuaDNWNkU3Z0JtOFxuRjNQdmNBZ0tKNGxSbUYvS3JlbjFrTEdJaE1KRDhaMWI5aFp3NGMwWWhRbEUvV2hHOWVaNHNxY0MvdzlqUERMbFxuNkJ6OHNZVWNzVW9VUzRmZDdxYmViS1FPZlBnaitNYkNJWnBSNXJsTlBiSnZWQXVodW5QV3NHR2lFazY5MDFnOVxuUWZjL05RTTdLeXllRVRLVTBGQzVUdHpPY0sySi9FdFZJVzVFUk8xdXFRS0JnUURXVTNZbEtMcGJrNVUvMmovQ1xuQmx4aVo0Wm1oMFBaRTd1TWQ4c1VhYU1aRTcxcnZLRnpBMWxGRjFpdHNERzFRL21wZTBHQWhUWnlEMkgrRnRyL1xuSnBvdk1STG5lWndEKzAwK2hqUGdRNitwa0JrWDc0UXlmL2R1SUVBV3FDaGtjVTlEbTB1M0hJeUpJVGFwQ24wSVxuWmhsSFRMWWViUnJmcmdmdDhxajJjbHgrVHdLQmdRREpyb3lpek83SmR4ZTZiYVdvOXZhdWd0bHBRRU5BWUtQS1xuV1dXTTNtUnBHdnJSVFVJRUswNU14MkwyN2J4cXFrSWc2MU1lUy9lVEpxUHdiWUE3RlZJbUttM3dnNC9tNUhvTFxuMmRLRXhKRjd1elpzVnVQN2JsQWJGU1JIaWZvS3RrbEhkdi80K1ZodG1rVEQ2UUJOZDBDWTNxbFZVdFhOaDNVd1xuNHBnQkNuaC8zd0tCZ1FDRTlzNXJDek5pTU5MOUJCZGQ5YmhHekZjVE1JT2xIcHJSOEZlcTJFWjQva2dibUxESVxudTZFY1BmbWo5NVUvRVdiSUFGR0l2QndrOHVvbVNtT2V1NElZR09mVGR4eVZVOGgrSzUvdlY4Nlk4VzYvN0xZa1xuNWtMSXJYVlZHUW5HRm8zSU1ZWHRtZWFPQkc3MnZDMEprdDNINEExMEh0ZjNRTzVtYm83b0pkYS8vUUtCZ0VhR1xuTUExNXhnSlREOHdVTFhxaEtXK3F0K1hUSC9FeUdmUlhRR2g3Ri9lZEJKb04vd2pBTC9ndlBNOEdJUDNYblpvdlxuVC9obkxpS1p2M2dDZ25XbXBmeE1sL2NqdWoxT0pkTmhEdmw0Vnp0Q0l1ek5rWmxKWU4rbmkvRXNNWEJ2Zjc1cVxud1dYSm8zOW9FNlhDSTJYelRuWm1YaVpFK2hpTnhwQWFuSGE0dDV4WEFvR0JBS3BxUDJteXBzT1lyZDd6VWZ0Z1xuTmROeUJMNm1uV2k5bjcyOXpjTStWcjd2OGp5RWtBNWVhd3NQTG1RODNaUjY5MjcvbUZmeXZyNmppZDNXWUN0VlxuREFkYU5GWHV3Vk9MckZ5N2RXYnJCUWQrbkxtd25IWlJYbEtvdGRMYkZVdmIyMCtQSnBybXBGbG83SC8ydW9ZOVxud05YaWRxK1NDWGw2K1hHQlZNSkdsUFQwXG4tLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tXG4iLAogICJjbGllbnRfZW1haWwiOiAiZmVlZC11cGxvYWRlckB1ZmwtMjAuaWFtLmdzZXJ2aWNlYWNjb3VudC5jb20iLAogICJjbGllbnRfaWQiOiAiMTA5OTAwOTkyNjIyNTgwMzI2MDM4IiwKICAiYXV0aF91cmkiOiAiaHR0cHM6Ly9hY2NvdW50cy5nb29nbGUuY29tL28vb2F1dGgyL2F1dGgiLAogICJ0b2tlbl91cmkiOiAiaHR0cHM6Ly9vYXV0aDIuZ29vZ2xlYXBpcy5jb20vdG9rZW4iLAogICJhdXRoX3Byb3ZpZGVyX3g1MDlfY2VydF91cmwiOiAiaHR0cHM6Ly93d3cuZ29vZ2xlYXBpcy5jb20vb2F1dGgyL3YxL2NlcnRzIiwKICAiY2xpZW50X3g1MDlfY2VydF91cmwiOiAiaHR0cHM6Ly93d3cuZ29vZ2xlYXBpcy5jb20vcm9ib3QvdjEvbWV0YWRhdGEveDUwOS9mZWVkLXVwbG9hZGVyJTQwdWZsLTIwLmlhbS5nc2VydmljZWFjY291bnQuY29tIgp9Cg==  
---
apiVersion: v1
kind: Secret
metadata:
  name: rmq-creds
type: Opaque
data:
  RMQ_PASSWORD: aW5wbGF5bGFicw==
---
```

## File: `env/dev/datadog-values.yaml`
- **File Size:** 1563 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** Remove logs of ingress nginx controller

```
# datadog:
#   # kubeStateMetricsEnabled: true
#   # kubeStateMetricsCore:
#   #   enabled: true
#   # autoDiscovery:
#   #   enabled: true
#   # networkMonitoring:
#   #   enabled: true
#   # apm:
#   #   enabled: true
#   apiKey: "da003684f1708bb2f070bdca9adc3b82"
#   site: "datadoghq.com"
#   logs:
#     enabled: true
#     containerCollectAll: true

# datadog:
#   apiKeyExistingSecret: datadog-secret
#   site: "datadoghq.com"
#   logs:
#     enabled: true
#     containerCollectAll: true
#   clusterName: "dev-fanclash"  # Set your cluster name here

datadog:
  apiKeyExistingSecret: datadog-secret
  site: "datadoghq.com"
  clusterName: "dev-fanclash"
  logs:
    enabled: true
    containerCollectAll: true
  containerExclude: "image:docker.io/cilium/* image:docker.io/coredns/* image:digitalocean/cpbridge:* image:registry.k8s.io/sig-storage/ csi-node-driver-registrar:* image:docker.io/digitalocean/do-csi-plugin:* image:docker.io/digitalocean/do-agent:* image:quay.io/cilium/hubble-* image:registry.k8s.io/kas-network-proxy/proxy-agent:* image:registry.k8s.io/kube-proxy:* image:gcr.io/datadoghq/agent:* image:gcr.io/datadoghq/cluster-agent:* image:docker.io/bitnami/rabbitmq* image:registry.k8s.io/ingress-nginx/controller:*"
  containerInclude: "image:registry.digitalocean.com/gameon-ams3/laliga-matchfantasy-api:* image:registry.digitalocean.com/gameon-ams3/laliga-matchfantasy-event-processor:* image:registry.digitalocean.com/gameon-ams3/laliga-matchfantasy-fcm-pusher:* image:registry.digitalocean.com/gameon-ams3/laliga-matchfantasy-admin:*"

```

## File: `env/prd/datadog-values.yaml`
- **File Size:** 886 bytes
- **Last Modified:** Tue Apr 22 2025 10:28:33 GMT-0500 (Peru Standard Time)
- **Last Commit:** db, cluster and vpn created

```
# # datadog:
# #   # kubeStateMetricsEnabled: true
# #   # kubeStateMetricsCore:
# #   #   enabled: true
# #   # autoDiscovery:
# #   #   enabled: true
# #   # networkMonitoring:
# #   #   enabled: true
# #   # apm:
# #   #   enabled: true
# #   apiKey: "da003684f1708bb2f070bdca9adc3b82"
# #   site: "datadoghq.com"
# #   logs:
# #     enabled: true
# #     containerCollectAll: true

# # datadog:
# #   apiKeyExistingSecret: datadog-secret
# #   site: "datadoghq.com"
# #   logs:
# #     enabled: true
# #     containerCollectAll: true
# #   clusterName: "dev-fanclash"  # Set your cluster name here

# datadog:
#   apiKeyExistingSecret: datadog-secret
#   site: "datadoghq.com"
#   clusterName: "fanclash-prd"
# #  containerExclude: "image:^registry.digitalocean.com/gameon-ams3/laliga-matchfantasy-rabbitmq-publisher$"
#   logs:
#     enabled: true
#     containerCollectAll: true

```
