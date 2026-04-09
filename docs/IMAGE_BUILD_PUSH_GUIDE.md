# Docker 이미지 빌드 및 KCR Push 가이드

> Kakao Cloud Container Registry (KCR)를 사용한 이미지 관리

## 📋 목차
- [사전 준비](#사전-준비)
- [Docker 로그인](#docker-로그인)
- [이미지 빌드 및 Push](#이미지-빌드-및-push)
- [Kubernetes에서 이미지 Pull](#kubernetes에서-이미지-pull)

---

## 사전 준비

### 1. KCR 레지스트리 정보

**레지스트리 주소**: `medi-bird.kr-central-2.kcr.dev`

**리포지토리 목록**:
- `cn-api-stage` - Staging API 이미지
- `cn-web-stage` - Staging Web 이미지
- `cn-api-prod` (필요시 생성) - Production API 이미지
- `cn-web-prod` (필요시 생성) - Production Web 이미지

### 2. IAM 액세스 키 확인

Kakao Cloud Console > IAM > 액세스 키 관리에서 발급받은:
- **액세스 키 ID**: `KCR_ACCESS_KEY_ID`
- **보안 액세스 키**: `KCR_SECRET_ACCESS_KEY`

---

## Docker 로그인

### 로컬 환경에서 로그인

```bash
docker login medi-bird.kr-central-2.kcr.dev \
  --username {액세스_키_ID} \
  --password {보안_액세스_키}
```

**예시**:
```bash
docker login medi-bird.kr-central-2.kcr.dev \
  --username AKIAXXX... \
  --password wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**로그인 성공 시**:
```
Login Succeeded
```

---

## 이미지 빌드 및 Push

### Staging 환경

#### 1. API 이미지 빌드

```bash
cd caring-note-api-server

# 이미지 빌드
docker build -t cn-api-stage:latest .

# KCR 태깅
docker tag cn-api-stage:latest \
  medi-bird.kr-central-2.kcr.dev/cn-api-stage/cn-api-stage:latest

# Git 커밋 해시로도 태깅 (버전 관리용)
GIT_HASH=$(git rev-parse --short HEAD)
docker tag cn-api-stage:latest \
  medi-bird.kr-central-2.kcr.dev/cn-api-stage/cn-api-stage:${GIT_HASH}

# KCR Push
docker push medi-bird.kr-central-2.kcr.dev/cn-api-stage/cn-api-stage:latest
docker push medi-bird.kr-central-2.kcr.dev/cn-api-stage/cn-api-stage:${GIT_HASH}
```

#### 2. Web 이미지 빌드

```bash
cd caring-note-web

# 이미지 빌드
docker build -t cn-web-stage:latest .

# KCR 태깅
docker tag cn-web-stage:latest \
  medi-bird.kr-central-2.kcr.dev/cn-web-stage/cn-web-stage:latest

# Git 커밋 해시로도 태깅
GIT_HASH=$(git rev-parse --short HEAD)
docker tag cn-web-stage:latest \
  medi-bird.kr-central-2.kcr.dev/cn-web-stage/cn-web-stage:${GIT_HASH}

# KCR Push
docker push medi-bird.kr-central-2.kcr.dev/cn-web-stage/cn-web-stage:latest
docker push medi-bird.kr-central-2.kcr.dev/cn-web-stage/cn-web-stage:${GIT_HASH}
```

---

### Production 환경

#### 1. Production 리포지토리 생성 (필요시)

Kakao Cloud Console > Container Registry에서:
- `cn-api-prod` 리포지토리 생성
- `cn-web-prod` 리포지토리 생성

#### 2. API 이미지 빌드 및 Push

```bash
cd caring-note-api-server

# 이미지 빌드
docker build -t cn-api-prod:latest .

# KCR 태깅
docker tag cn-api-prod:latest \
  medi-bird.kr-central-2.kcr.dev/cn-api-prod/cn-api-prod:latest

GIT_HASH=$(git rev-parse --short HEAD)
docker tag cn-api-prod:latest \
  medi-bird.kr-central-2.kcr.dev/cn-api-prod/cn-api-prod:${GIT_HASH}

# KCR Push
docker push medi-bird.kr-central-2.kcr.dev/cn-api-prod/cn-api-prod:latest
docker push medi-bird.kr-central-2.kcr.dev/cn-api-prod/cn-api-prod:${GIT_HASH}
```

#### 3. Web 이미지 빌드 및 Push

```bash
cd caring-note-web

# 이미지 빌드
docker build -t cn-web-prod:latest .

# KCR 태깅
docker tag cn-web-prod:latest \
  medi-bird.kr-central-2.kcr.dev/cn-web-prod/cn-web-prod:latest

GIT_HASH=$(git rev-parse --short HEAD)
docker tag cn-web-prod:latest \
  medi-bird.kr-central-2.kcr.dev/cn-web-prod/cn-web-prod:${GIT_HASH}

# KCR Push
docker push medi-bird.kr-central-2.kcr.dev/cn-web-prod/cn-web-prod:latest
docker push medi-bird.kr-central-2.kcr.dev/cn-web-prod/cn-web-prod:${GIT_HASH}
```

---

## Kubernetes에서 이미지 Pull

### 1. kcr-secret 생성

이미 GitHub Actions 워크플로우로 생성했다면 Skip.

```bash
kubectl create secret docker-registry kcr-secret \
  --docker-server=medi-bird.kr-central-2.kcr.dev \
  --docker-username={액세스_키_ID} \
  --docker-password={보안_액세스_키} \
  --namespace=default
```

### 2. Deployment에서 사용

`staging/api.yaml` 예시:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: caring-note-api
spec:
  template:
    spec:
      imagePullSecrets:
        - name: kcr-secret  # ✅ Secret 참조
      containers:
        - name: caring-note-api
          image: medi-bird.kr-central-2.kcr.dev/cn-api-stage/cn-api-stage:latest
          imagePullPolicy: Always
```

### 3. 이미지 Pull 테스트

```bash
# Staging VM에서
kubectl run test-pod \
  --image=medi-bird.kr-central-2.kcr.dev/cn-api-stage/cn-api-stage:latest \
  --overrides='{"spec": {"imagePullSecrets": [{"name": "kcr-secret"}]}}' \
  --rm -it --restart=Never \
  -- /bin/sh

# Pull 성공 확인
kubectl get pods
```

---

## 자동화 스크립트

### 빌드 및 Push 자동화

`build-and-push.sh`:
```bash
#!/bin/bash
set -e

# 환경 변수
REGISTRY="medi-bird.kr-central-2.kcr.dev"
ENV=${1:-staging}  # staging or prod
SERVICE=${2:-api}  # api or web

# Git 해시
GIT_HASH=$(git rev-parse --short HEAD)

# 환경에 따른 설정
if [ "$ENV" = "staging" ]; then
    REPO_API="cn-api-stage"
    REPO_WEB="cn-web-stage"
else
    REPO_API="cn-api-prod"
    REPO_WEB="cn-web-prod"
fi

# 서비스에 따른 처리
if [ "$SERVICE" = "api" ]; then
    IMAGE_NAME="${REPO_API}"
    BUILD_DIR="../caring-note-api-server"
elif [ "$SERVICE" = "web" ]; then
    IMAGE_NAME="${REPO_WEB}"
    BUILD_DIR="../caring-note-web"
else
    echo "Error: SERVICE must be 'api' or 'web'"
    exit 1
fi

echo "Building $SERVICE for $ENV environment..."

# 빌드
cd $BUILD_DIR
docker build -t $IMAGE_NAME:latest .

# 태깅
docker tag $IMAGE_NAME:latest ${REGISTRY}/${IMAGE_NAME}/${IMAGE_NAME}:latest
docker tag $IMAGE_NAME:latest ${REGISTRY}/${IMAGE_NAME}/${IMAGE_NAME}:${GIT_HASH}

# Push
echo "Pushing to KCR..."
docker push ${REGISTRY}/${IMAGE_NAME}/${IMAGE_NAME}:latest
docker push ${REGISTRY}/${IMAGE_NAME}/${IMAGE_NAME}:${GIT_HASH}

echo "✅ Successfully pushed:"
echo "  - ${REGISTRY}/${IMAGE_NAME}/${IMAGE_NAME}:latest"
echo "  - ${REGISTRY}/${IMAGE_NAME}/${IMAGE_NAME}:${GIT_HASH}"
```

**사용법**:
```bash
# Staging API 빌드 및 Push
./build-and-push.sh staging api

# Staging Web 빌드 및 Push
./build-and-push.sh staging web

# Production API 빌드 및 Push
./build-and-push.sh prod api
```

---

## 이미지 조회

### KCR에 Push된 이미지 확인

```bash
# KCR CLI 사용 (설치 필요)
kcr images list --repository cn-api-stage

# 또는 Kakao Cloud Console에서 확인
# Container Registry > 리포지토리 > cn-api-stage
```

### Kubernetes에서 사용 중인 이미지 확인

```bash
# 현재 실행 중인 Pod의 이미지 확인
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Deployment의 이미지 확인
kubectl get deployment caring-note-api -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## 트러블슈팅

### 1. 로그인 실패

**에러**: `Error response from daemon: Get https://medi-bird.kr-central-2.kcr.dev/v2/: unauthorized`

**해결**:
```bash
# 액세스 키 확인
# Kakao Cloud Console > IAM > 액세스 키 관리

# 재로그인
docker logout medi-bird.kr-central-2.kcr.dev
docker login medi-bird.kr-central-2.kcr.dev --username {액세스_키_ID} --password {보안_액세스_키}
```

### 2. Push 권한 없음

**에러**: `denied: requested access to the resource is denied`

**해결**:
- IAM 액세스 키에 Container Registry 쓰기 권한 있는지 확인
- 리포지토리 이름 확인 (대소문자 구분)

### 3. Kubernetes ImagePullBackOff

**에러**: `Failed to pull image ... : rpc error: code = Unknown desc = Error response from daemon: pull access denied`

**해결**:
```bash
# kcr-secret 확인
kubectl get secret kcr-secret -n default

# 없으면 생성
kubectl create secret docker-registry kcr-secret \
  --docker-server=medi-bird.kr-central-2.kcr.dev \
  --docker-username={액세스_키_ID} \
  --docker-password={보안_액세스_키}

# Deployment에 imagePullSecrets 추가 확인
kubectl get deployment caring-note-api -o yaml | grep imagePullSecrets -A 2
```

### 4. 이미지 이름 오류

**현재 설정**:
```
레지스트리: medi-bird.kr-central-2.kcr.dev
리포지토리: cn-api-stage
이미지 이름: cn-api-stage
태그: latest

전체 경로: medi-bird.kr-central-2.kcr.dev/cn-api-stage/cn-api-stage:latest
```

**잘못된 예시**:
```
❌ kr-central-2-registry.kr.kcr.dev/caring-note-registry/cn-api-stage:latest
✅ medi-bird.kr-central-2.kcr.dev/cn-api-stage/cn-api-stage:latest
```

---

## 참고 자료

- [Kakao Cloud Container Registry 문서](https://docs.kakaoi.ai/kakao_cloud/container_registry/)
- [Docker 공식 문서](https://docs.docker.com/)
- [Kubernetes imagePullSecrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

---

**문서 버전**: 1.0
**최종 수정일**: 2025-01-11
