# Staging VM 초기 설정 가이드

> 작성일: 2025-11-08
> 대상: Staging VM (caring-note-staging-vm)
> 예상 소요 시간: 1-2시간

---

## 목차
- [사전 준비](#사전-준비)
- [1단계: SSH 접속 및 기본 설정](#1단계-ssh-접속-및-기본-설정)
- [2단계: Docker 설치](#2단계-docker-설치)
- [3단계: Kubernetes 설치](#3단계-kubernetes-설치)
- [4단계: 데이터 볼륨 마운트](#4단계-데이터-볼륨-마운트)
- [5단계: Helm 설치](#5단계-helm-설치)
- [6단계: 기본 컴포넌트 설치](#6단계-기본-컴포넌트-설치)
- [7단계: Kubernetes Secrets 생성](#7단계-kubernetes-secrets-생성)
- [검증 체크리스트](#검증-체크리스트)

---

## 사전 준비

### 필요한 정보
- Staging VM Public IP: `<STAGING_VM_IP>`
- SSH Key 파일: `caring-note-staging-key.pem`
- Subnet CIDR: `10.0.96.0/20`
- AZ: `kr-central-2-a`

### 로컬 환경 설정
```bash
# SSH Key 권한 설정
chmod 400 ~/Downloads/caring-note-staging-key.pem

# SSH Config 추가 (선택사항)
cat >> ~/.ssh/config <<EOF

Host staging-vm
    HostName <STAGING_VM_IP>
    User ubuntu
    IdentityFile ~/Downloads/caring-note-staging-key.pem
EOF
```

---

## 1단계: SSH 접속 및 기본 설정

### SSH 접속
```bash
# 방법 1: 직접 접속
ssh -i ~/Downloads/caring-note-staging-key.pem ubuntu@<STAGING_VM_IP>

# 방법 2: SSH Config 사용 (위에서 설정한 경우)
ssh staging-vm
```

### 시스템 업데이트
```bash
# 패키지 목록 업데이트
sudo apt update

# 설치된 패키지 업그레이드
sudo apt upgrade -y

# 재부팅 필요 여부 확인
if [ -f /var/run/reboot-required ]; then
    echo "재부팅이 필요합니다"
    sudo reboot
    # 재부팅 후 다시 SSH 접속
fi
```

### 기본 패키지 설치
```bash
# 필수 도구 설치
sudo apt install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    net-tools \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    gnupg \
    lsb-release

# 타임존 설정
sudo timedatectl set-timezone Asia/Seoul

# 확인
date
timedatectl
```

### 호스트명 설정 (선택)
```bash
# 호스트명 변경
sudo hostnamectl set-hostname caring-note-staging-vm

# /etc/hosts 업데이트
echo "127.0.0.1 caring-note-staging-vm" | sudo tee -a /etc/hosts

# 확인
hostname
```

---

## 2단계: Container Runtime 설치 (containerd)

**ℹ️ Kubernetes 1.24+는 Docker 대신 containerd를 사용합니다.**

### containerd 설치
```bash
# containerd 설치
sudo apt update
sudo apt install -y containerd

# containerd 서비스 활성화
sudo systemctl enable containerd
sudo systemctl start containerd

# containerd 버전 확인
containerd --version
# 예상 출력: containerd github.com/containerd/containerd v1.7.x 또는 v2.x.x
```

### containerd 설정 생성

**⚠️ 중요: 명령어를 한 줄로 입력해야 합니다!**

```bash
# 1. 설정 디렉토리 생성
sudo mkdir -p /etc/containerd

# 2. 기본 설정 생성 (한 줄로 입력!)
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# 3. SystemdCgroup 활성화 (Kubernetes 요구사항)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# 4. 변경 확인
grep SystemdCgroup /etc/containerd/config.toml
# 출력: SystemdCgroup = true 여야 함

# 5. containerd 재시작
sudo systemctl restart containerd

# 6. containerd 상태 확인
sudo systemctl status containerd
# Active (running) 상태여야 함
```

### crictl 설정 (Container Runtime CLI)

```bash
# crictl 설정 파일 생성
sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# crictl 버전 확인
sudo crictl version

# 예상 출력:
# Version:  0.1.0
# RuntimeName:  containerd
# RuntimeVersion:  v1.7.x 또는 v2.x.x
# RuntimeApiVersion:  v1
```

### containerd 동작 확인

```bash
# 1. containerd 소켓 파일 확인
ls -la /run/containerd/containerd.sock
# 출력: srw-rw---- 1 root root ... /run/containerd/containerd.sock

# 2. crictl로 이미지 목록 확인 (비어있어도 정상)
sudo crictl images

# 3. containerd 서비스 상태
systemctl is-active containerd
# 출력: active
```

### Docker 설치 (선택사항)

**ℹ️ containerd만으로 Kubernetes 사용 가능합니다. Docker는 선택사항입니다.**

Docker 명령어를 사용하고 싶다면:

```bash
# Docker 설치 (containerd 위에 설치됨)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER
newgrp docker

# Docker 확인
docker --version
docker ps

# 주의: Docker를 설치해도 Kubernetes는 containerd를 직접 사용합니다.
```

---

## 3단계: Kubernetes 설치

### 사전 설정
```bash
# Swap 비활성화 (Kubernetes 요구사항)
sudo swapoff -a

# 영구적으로 비활성화
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 확인
free -h
# Swap이 0이어야 함

# 커널 모듈 로드
sudo modprobe overlay
sudo modprobe br_netfilter

# 부팅 시 자동 로드 설정
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# sysctl 파라미터 설정
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# 설정 적용
sudo sysctl --system
```

### Kubernetes 패키지 저장소 추가
```bash
# Kubernetes 버전 설정 (v1.28 권장)
KUBE_VERSION="v1.28"

# GPG 키 다운로드
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 저장소 추가
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list
```

### kubeadm, kubelet, kubectl 설치
```bash
# 패키지 목록 업데이트
sudo apt update

# Kubernetes 패키지 설치
sudo apt install -y kubelet kubeadm kubectl

# 자동 업그레이드 방지 (버전 고정)
sudo apt-mark hold kubelet kubeadm kubectl

# 버전 확인
kubeadm version
kubectl version --client
```

### Kubernetes 클러스터 초기화
```bash
# 클러스터 초기화 (Pod 네트워크 CIDR 지정)
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# 성공 메시지가 출력되면 아래 내용 복사해두기:
# - kubeadm join 명령어 (나중에 노드 추가 시 필요)
# - kubectl 설정 명령어

# 예시 출력:
# Your Kubernetes control-plane has initialized successfully!
#
# To start using your cluster, you need to run the following as a regular user:
#
#   mkdir -p $HOME/.kube
#   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#   sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### kubectl 설정
```bash
# kubectl 설정 디렉토리 생성
mkdir -p $HOME/.kube

# admin config 복사
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# 소유권 변경
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 확인
kubectl cluster-info
kubectl get nodes
# 현재는 NotReady 상태 (CNI 플러그인 설치 전)
```

### CNI 플러그인 설치 (Flannel)
```bash
# Flannel 설치
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Pod 생성 확인 (1-2분 소요)
kubectl get pods -n kube-flannel

# 노드 상태 확인
kubectl get nodes
# STATUS가 Ready로 변경되면 성공
```

### 단일 노드 설정 (Master Taint 제거)
```bash
# Master 노드에서도 Pod 실행 가능하도록 Taint 제거
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 확인
kubectl describe node | grep Taints
# Taints: <none> 이면 성공
```

### Kubernetes 시스템 Pod 확인
```bash
# 모든 시스템 Pod 확인
kubectl get pods -A

# 모두 Running 상태여야 함:
# - kube-system: coredns, etcd, kube-apiserver, kube-controller-manager, kube-proxy, kube-scheduler
# - kube-flannel: kube-flannel-ds
```

---

## 4단계: 데이터 볼륨 마운트

### 블록 디바이스 확인
```bash
# 연결된 디스크 확인
lsblk

# 예상 출력:
# NAME    MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
# vda       8:0    0   100G  0 disk
# └─vda1    8:1    0   100G  0 part /
# vdb       8:16   0   512G  0 disk  ← 추가 볼륨
```

### 파일시스템 생성 및 마운트
```bash
# 파일시스템 생성 (최초 1회만)
sudo mkfs.ext4 /dev/vdb

# 마운트 포인트 생성
sudo mkdir -p /mnt/data

# 임시 마운트
sudo mount /dev/vdb /mnt/data

# 마운트 확인
df -h | grep /mnt/data
# /dev/vdb        503G   28K  478G   1% /mnt/data

# 권한 설정
sudo chmod 755 /mnt/data
```

### 영구 마운트 설정
```bash
# UUID 확인
sudo blkid /dev/vdb
# 출력 예시: /dev/vdb: UUID="xxxx-xxxx-xxxx-xxxx" TYPE="ext4"

# /etc/fstab에 추가 (재부팅 후에도 자동 마운트)
echo "/dev/vdb /mnt/data ext4 defaults 0 0" | sudo tee -a /etc/fstab

# fstab 검증
sudo mount -a

# 재부팅 테스트 (선택)
# sudo reboot
# df -h | grep /mnt/data  # 재부팅 후에도 마운트되어 있어야 함
```

### PostgreSQL 데이터 디렉토리 생성
```bash
# Staging PostgreSQL 데이터 디렉토리
sudo mkdir -p /mnt/data/postgresql-staging

# Kubernetes에서 접근 가능하도록 권한 설정
sudo chmod 777 /mnt/data/postgresql-staging

# 확인
ls -la /mnt/data/
```

---

## 5단계: Helm 설치

### Git Repository Clone
```bash
# 홈 디렉토리로 이동
cd ~

# Repository clone
git clone https://github.com/tech-for-impact/caring-note-deployment.git

# 디렉토리 이동
cd caring-note-deployment
```

### Helm 설치
```bash
# 기존 스크립트 사용
chmod +x common/get_helm.sh
./common/get_helm.sh

# 또는 수동 설치:
# curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Helm 버전 확인
helm version
# version.BuildInfo{Version:"v3.x.x", ...}

# Helm 저장소 추가
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 저장소 확인
helm repo list
```

---

## 6단계: 기본 컴포넌트 설치

### Nginx Ingress Controller 설치
```bash
# Ingress Nginx 설치
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --wait

# 설치 확인
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# NodePort 확인
kubectl get svc ingress-nginx-controller -n ingress-nginx
# PORT(S) 열에서 80:30080/TCP, 443:30443/TCP 확인
```

### cert-manager 설치
```bash
# cert-manager 설치
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# 설치 확인 (1-2분 소요)
kubectl get pods -n cert-manager

# 모든 Pod가 Running 상태여야 함:
# - cert-manager
# - cert-manager-cainjector
# - cert-manager-webhook
```

### ClusterIssuer 적용
```bash
# Let's Encrypt ClusterIssuer 적용
kubectl apply -f common/cluster-issuer.yaml

# 확인
kubectl get clusterissuer

# letsencrypt-cluster-issuer가 Ready 상태여야 함
```

### 방화벽 설정 확인
```bash
# Kakao Cloud 보안 그룹에서 아래 포트가 열려있는지 확인:
# - TCP 80 (HTTP)
# - TCP 443 (HTTPS)
# - TCP 30080 (NodePort HTTP)
# - TCP 30443 (NodePort HTTPS)

# VM에서 포트 리스닝 확인
sudo netstat -tlnp | grep -E ':(80|443|30080|30443)'
```

---

## 7단계: Namespace 생성

### caring-note-staging namespace 생성

```bash
# Staging 전용 namespace 생성
kubectl create namespace caring-note-staging

# 확인
kubectl get namespaces

# caring-note-staging이 Active 상태여야 함
```

---

## 8단계: Kubernetes Secrets 생성

### Self-Hosted Runner 설치 (권장)

**⚠️ 보안상 Self-Hosted Runner 사용을 권장합니다!**

```bash
# GitHub Repository → Settings → Actions → Runners → New self-hosted runner
# 나오는 명령어를 따라 실행

# Runner 디렉토리 생성
mkdir -p ~/actions-runner && cd ~/actions-runner

# 다운로드 및 설치 (GitHub에서 제공하는 명령어 실행)
# ...

# 설정 시 라벨: staging 입력
./config.sh --url https://github.com/tech-for-impact/caring-note-deployment --token <TOKEN>

# 서비스로 등록
sudo ./svc.sh install
sudo ./svc.sh start
```

**Self-Hosted Runner 설치 후:**

1. **GitHub Secrets 설정** (Repository → Settings → Environments → staging → Environment secrets):
   - `DB_USERNAME`: `postgres`
   - `DB_PASSWORD`: 강력한 비밀번호 생성 (`openssl rand -base64 32`)
   - `POSTGRES_PASSWORD`: 강력한 비밀번호
   - `KEYCLOAK_ADMIN_PASSWORD`: 강력한 비밀번호
   - `KEYCLOAK_DB_PASSWORD`: 강력한 비밀번호
   - `OPENAI_API_KEY`: OpenAI API Key
   - `CLOVA_API_KEY`: Naver Clova API Key
   - `KCR_ACCESS_KEY_ID`: Kakao Cloud Container Registry Access Key
   - `KCR_SECRET_ACCESS_KEY`: Kakao Cloud Container Registry Secret Key

2. **GitHub Actions 실행**:
   - Repository → Actions → "Deploy Kubernetes Secrets" 워크플로우
   - **Run workflow** 클릭
   - Environment: **staging** 선택
   - Secrets가 자동으로 생성됨

### Secret 생성 확인

```bash
# 1. Secret 목록 확인
kubectl get secrets -n caring-note-staging

# 예상 출력 (5개 있어야 함):
# NAME                  TYPE                             DATA   AGE
# api-secret            Opaque                           4      1m
# kcr-secret            kubernetes.io/dockerconfigjson   1      1m
# keycloak              Opaque                           1      1m
# keycloak-externaldb   Opaque                           1      1m
# postgresql            Opaque                           2      1m

# 2. 각 Secret 상세 확인
kubectl describe secret api-secret -n caring-note-staging
kubectl describe secret postgresql -n caring-note-staging
kubectl describe secret keycloak -n caring-note-staging
kubectl describe secret keycloak-externaldb -n caring-note-staging
kubectl describe secret kcr-secret -n caring-note-staging

# 3. Secret 값 확인 (Base64 디코드)
kubectl get secret postgresql -n caring-note-staging -o jsonpath='{.data.postgres-password}' | base64 -d
echo ""

kubectl get secret keycloak -n caring-note-staging -o jsonpath='{.data.admin-password}' | base64 -d
echo ""

# 4. 모든 Secret의 키 목록 확인
kubectl get secret api-secret -n caring-note-staging -o json | jq '.data | keys'
# 예상: ["CLOVA_API_KEY", "OPEN_AI_API_KEY", "SPRING_DATASOURCE_PASSWORD", "SPRING_DATASOURCE_USERNAME"]
```

### 체크리스트

다음 5개 Secret이 모두 있어야 합니다:
- [ ] `kcr-secret` - Container Registry 인증
- [ ] `api-secret` - API 환경변수 (DB, OpenAI, Clova)
- [ ] `postgresql` - PostgreSQL 비밀번호
- [ ] `keycloak` - Keycloak Admin 비밀번호
- [ ] `keycloak-externaldb` - Keycloak DB 비밀번호

---

## 검증 체크리스트

### 기본 환경
- [ ] SSH 접속 가능
- [ ] 시스템 업데이트 완료
- [ ] 기본 패키지 설치 완료
- [ ] 타임존 설정 완료 (Asia/Seoul)

### Docker
- [ ] Docker 설치 완료 (`docker --version`)
- [ ] Docker 서비스 실행 중 (`systemctl status docker`)
- [ ] 현재 사용자 docker 그룹 추가
- [ ] `docker run hello-world` 성공

### Kubernetes
- [ ] kubeadm, kubelet, kubectl 설치 완료
- [ ] 클러스터 초기화 완료 (`kubeadm init`)
- [ ] kubectl 설정 완료 (`kubectl get nodes`)
- [ ] CNI 플러그인 설치 완료 (Flannel)
- [ ] 노드 상태 Ready (`kubectl get nodes`)
- [ ] Master taint 제거 완료
- [ ] 시스템 Pod 모두 Running (`kubectl get pods -A`)

### 스토리지
- [ ] 추가 볼륨 마운트 완료 (`/mnt/data`)
- [ ] /etc/fstab 설정 완료
- [ ] PostgreSQL 데이터 디렉토리 생성 완료

### Helm 및 기본 컴포넌트
- [ ] Git repository clone 완료
- [ ] Helm 설치 완료 (`helm version`)
- [ ] Nginx Ingress Controller 설치 완료
- [ ] cert-manager 설치 완료
- [ ] ClusterIssuer 생성 완료

### Namespace 및 Self-Hosted Runner
- [ ] caring-note-staging namespace 생성 완료
- [ ] Self-Hosted Runner 설치 완료
- [ ] GitHub Secrets 설정 완료 (Environment secrets)
- [ ] GitHub Actions "Deploy Kubernetes Secrets" 워크플로우 실행 완료

### Secrets
- [ ] kcr-secret 생성 완료 (`kubectl get secret kcr-secret -n caring-note-staging`)
- [ ] api-secret 생성 완료 (`kubectl get secret api-secret -n caring-note-staging`)
- [ ] postgresql 생성 완료 (`kubectl get secret postgresql -n caring-note-staging`)
- [ ] keycloak 생성 완료 (`kubectl get secret keycloak -n caring-note-staging`)
- [ ] keycloak-externaldb 생성 완료 (`kubectl get secret keycloak-externaldb -n caring-note-staging`)

### 최종 확인
```bash
# 모든 Pod가 Running 상태인지 확인
kubectl get pods -A

# Secret이 모두 생성되었는지 확인 (5개 있어야 함)
kubectl get secrets -n caring-note-staging

# Ingress Controller가 정상 동작하는지 확인
kubectl get svc -n ingress-nginx

# cert-manager가 정상 동작하는지 확인
kubectl get pods -n cert-manager
```

---

## 다음 단계

모든 체크리스트를 완료했다면:

```bash
# Staging 디렉토리로 이동
cd ~/caring-note-deployment/staging

# 배포 스크립트 실행
./deploy-staging.sh
```

배포 완료 후:
1. DNS 설정: `stage.caringnote.co.kr` → Staging VM IP
2. SSL 인증서 발급 확인: `kubectl get certificate -n caring-note-staging`
3. 애플리케이션 접속 테스트: `https://stage.caringnote.co.kr`

---

## 트러블슈팅

### Docker 권한 오류
```bash
# 에러: permission denied while trying to connect to the Docker daemon
newgrp docker
# 또는 로그아웃 후 재로그인
```

### Kubernetes Pod가 Pending 상태
```bash
# 상세 정보 확인
kubectl describe pod <pod-name>

# Taint 확인
kubectl describe node | grep Taints

# Taint 제거
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### CNI 플러그인 오류
```bash
# Flannel Pod 확인
kubectl get pods -n kube-flannel

# 로그 확인
kubectl logs -n kube-flannel <flannel-pod-name>

# 재설치
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### Ingress Controller 접속 불가
```bash
# NodePort 확인
kubectl get svc -n ingress-nginx

# 보안 그룹에서 30080, 30443 포트 확인
# Kakao Cloud Console에서 보안 그룹 규칙 추가
```

---

**문서 버전**: 1.0
**최종 업데이트**: 2025-11-08
