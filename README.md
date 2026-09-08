# Mecânica DM - Infraestrutura Kubernetes (Terraform + Helm)

![Kubernetes](https://img.shields.io/badge/K8s-1.32-blue?logo=kubernetes)
![Terraform](https://img.shields.io/badge/Terraform-1.8.0-purple?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-EKS-orange?logo=amazon-aws)

Repositório de infraestrutura que provisiona e gerencia o cluster **Amazon EKS** e todos os add-ons necessários para rodar a API **Mecânica DM** em produção — incluindo API Gateway (Kong), autoscaling (HPA), secrets management (External Secrets Operator), DNS (Route 53 + ExternalDNS) e observabilidade (New Relic).

Na **Fase 03** do 15SOAT, este repositório abriga toda a camada de infraestrutura como código (IaC), separado do código da aplicação (`mecanicadm-api-v3`), da Lambda de validação de CPF (`mecanicadm-lambda-v3`) e do banco de dados (`db-v3`).

---

## 📚 Documentação

### Componenetes de infraestrutura

![Componentes de infraestrutura](docs/assets/c4-componentes-infra-mecanicadm.png)

---

## 🏁 Como Começar

### Pré-requisitos

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configurado com credenciais de acesso
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.8.0
- [kubectl](https://kubernetes.io/pt-br/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.x

### 1. Configurar as Variáveis do GitHub Actions

No repositório GitHub, configure os seguintes **Secrets**:

| Secret | Descrição |
|--------|-----------|
| `AWS_ACCESS_KEY_ID` | Chave de acesso AWS (IAM com permissões EKS, S3, SSM, Route 53, Lambda) |
| `AWS_SECRET_ACCESS_KEY` | Chave secreta AWS |
| `NEW_RELIC_LICENSE_KEY` | License key da New Relic |
| `MAIL_USERNAME` | Usuário SMTP (Gmail) |
| `MAIL_PASSWORD` | Senha SMTP (App Password do Gmail) |
| `DOCKER_IMAGE` | Imagem Docker da API (ex.: `diegopriess/mecanica-dm`) |

E as seguintes **Variables**:

| Variable | Descrição | Padrão |
|----------|-----------|--------|
| `AWS_REGION` | Região AWS | `us-east-1` |
| `TF_STATE_BUCKET` | Nome do bucket S3 para o state | — |
| `EKS_CLUSTER_NAME` | Nome do cluster EKS | `mecanicadm-prod` |

### 2. Criar a Hosted Zone DNS (primeira vez)

Execute o workflow **DNS - Hosted Zone Route 53** via GitHub Actions (manual). Após a criação, copie os nameservers exibidos e cadastre-os no painel do [Registro.br](https://registro.br) para o domínio `mecanicadm.com.br`.

### 3. Provisionar a Infraestrutura

Execute o workflow **CI/CD - Terraform EKS + Helm** (push na main ou manual). Ele irá:

1. Criar o bucket S3 para o state (se não existir)
2. Executar `terraform init`, `fmt`, `validate`, `plan` e `apply`
3. Atualizar o kubeconfig do EKS
4. Reiniciar o ExternalDNS e verificar a injeção do IRSA

### 4. Deploy da Aplicação

O workflow **Deploy Aplicação - Helm** é disparado automaticamente quando:
- Arquivos em `helm/**` são alterados na main
- O repo `mecanicadm-api-v3` publica uma nova imagem (`repository_dispatch`)
- Executado manualmente (com tag de imagem opcional)

---

## 🔧 Comandos Úteis

### Verificar os recursos do cluster

```bash
kubectl get all -n mecanicadm
kubectl get all -n kong
```

### Verificar o status do HPA

```bash
kubectl get hpa -n mecanicadm
```

### Verificar os External Secrets

```bash
kubectl get externalsecrets -n mecanicadm
kubectl get secrets -n mecanicadm
```

### Verificar o ExternalDNS

```bash
kubectl get pods -n external-dns
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=50
```

### Verificar o Kong

```bash
kubectl get ingress -n mecanicadm
kubectl get svc -n kong
```

### Logs da aplicação

```bash
kubectl logs -n mecanicadm -l app.kubernetes.io/name=mecanicadm --tail=100 -f
```

---

## ⚠️ Destruir a Infraestrutura

Execute o workflow **DESTROY** via GitHub Actions (manual). É necessário digitar **"DESTRUIR"** no campo de confirmação. O workflow irá:

1. Executar `terraform destroy -auto-approve`
2. Verificar recursos órfãos (Load Balancers, IPs Elásticos, NAT Gateways)

> **Atenção**: A zona DNS (`dns/`) possui state separado e **não** é destruída junto com a infraestrutura principal.

---

## Pipes

Visão geral das 4 pipelines (`.github/workflows/`):

```mermaid
flowchart LR
    TRIGGER{Evento} -->|push: main| CICD[CI/CD - Terraform EKS + Helm<br/>ci-cd.yml]
    TRIGGER -->|pull_request| CICD
    TRIGGER -->|workflow_dispatch| CICD
    TRIGGER -->|"push: main (helm/**)"| DEPLOY[Deploy Aplicação - Helm<br/>app-deploy.yml]
    TRIGGER -->|repository_dispatch<br/>app-image-published| DEPLOY
    TRIGGER -->|workflow_dispatch<br/>image_tag| DEPLOY
    TRIGGER -->|workflow_dispatch manual| DNS[DNS - Hosted Zone Route 53<br/>dns.yml]
    TRIGGER -->|workflow_dispatch manual<br/>confirmação = DESTRUIR| DESTROY[DESTROY - Infraestrutura K8s<br/>destroy.yml]
```

### CI/CD - Terraform EKS + Helm (`ci-cd.yml`)

Disparado por push na `main`, pull request ou manualmente. Valida e aplica a infraestrutura Terraform, e depois de aplicada, prepara o ambiente para o deploy.

```mermaid
flowchart TD
    TRIGGER{Evento} -->|push: main| TF
    TRIGGER -->|pull_request| TF
    TRIGGER -->|workflow_dispatch| TF

    subgraph TF[Job: terraform]
        direction LR
        A1[Checkout] --> A2[Configurar credenciais AWS]
        A2 --> A3[Setup Terraform 1.8.0]
        A3 --> A4[Garantir bucket S3 backend<br/>create + versioning + KMS]
        A4 --> A5[Terraform Init]
        A5 --> A6[Terraform Fmt -check -diff]
        A6 --> A7[Terraform Validate]
        A7 --> A8[Terraform Plan]

        A8 --> A9{O push em main<br/>ou workflow_dispatch?}
        A9 -->|sim| A10[Terraform Apply -auto-approve]
        A9 -->|não| FIM1[Fim - sem apply<br/>PR apenas valida]
        A10 --> A11[Terraform Outputs]
        A11 --> A12[Update kubeconfig EKS]

        A12 --> A13[Reiniciar ExternalDNS<br/>rollout restart]
        A13 --> A14{IRSA injetado no pod?}
        A14 -->|sim| OK[✔ Sucesso]
        A14 -->|não| FAIL[✘ Falha<br/>link do webhook de identidade]
    end
```

### Deploy Aplicação - Helm (`app-deploy.yml`)

Disparado por push na `main` (alterações em `helm/**`), por `repository_dispatch` do repo da API (`app-image-published`) ou manualmente. Instala/atualiza a aplicação no cluster via Helm.

```mermaid
flowchart TD
    TRIGGER{Evento} -->|"push: main<br/>paths: helm/**"| D
    TRIGGER -->|repository_dispatch<br/>app-image-published| D
    TRIGGER -->|workflow_dispatch<br/>input: image_tag| D

    subgraph D[Job: deploy]
        direction LR
        S1[Checkout] --> S2[Configurar credenciais AWS]
        S2 --> S3[Update kubeconfig EKS]
        S3 --> S4[Garantir namespace<br/>mecanicadm]
        S4 --> S5[Criar Secret da aplicação<br/>MAIL_USERNAME + MAIL_PASSWORD + NEW_RELIC_LICENSE_KEY]
        S5 --> S6["Definir tag da imagem<br/>client_payload || input || prod-latest"]
        S6 --> S7[helm upgrade --install<br/>values-prod.yaml + --atomic --timeout 5m]
        S7 --> S8[Verificar rollout<br/>kubectl rollout status]
    end
```

### DNS - Hosted Zone Route 53 (`dns.yml`)

Disparado manualmente. Executa o módulo Terraform `dns/` (state separado) para criar a hosted zone pública e exibir os nameservers para delegação no Registro.br.

```mermaid
flowchart TD
    TRIGGER[workflow_dispatch manual] --> J

    subgraph J[Job: dns]
        direction LR
        T1[Checkout] --> T2[Configurar credenciais AWS]
        T2 --> T3[Setup Terraform]
        T3 --> T4[Terraform Init<br/>working-directory: dns]
        T4 --> T5[Terraform Apply -auto-approve<br/>cria hosted zone pública]
        T5 --> T6[Exibir nameservers<br/>cadastro no painel.registro.br]
    end
```

### DESTROY - Infraestrutura K8s (`destroy.yml`)

Botão vermelho: disparado apenas manualmente e apenas com a confirmação exata **DESTRUIR**. Executa o `terraform destroy` e verifica recursos órfãos. Timeout de 60 minutos.

```mermaid
flowchart TD
    TRIGGER[workflow_dispatch manual<br/>input: confirmação] --> CONF{Confirmação ==<br/>DESTRUIR?}
    CONF -->|não| FIM[Workflow não executa]
    CONF -->|sim| J

    subgraph J[Job: destroy<br/>timeout 60min]
        direction LR
        E1[Checkout] --> E2[Configurar credenciais AWS]
        E2 --> E3[Setup Terraform]
        E3 --> E4[Terraform Init]
        E4 --> E5[Terraform Destroy -auto-approve<br/>~10 min cluster + NLB Kong]
        E5 --> E6[Verificar órfãos - informativo<br/>Load Balancers / EIP / NAT Gateways]
        E6 --> E7[Se houver órfãos<br/>apagar manualmente pelo console]
    end
```

