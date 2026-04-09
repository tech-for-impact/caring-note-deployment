# 보안 및 권한 관리 체계 재점검

> 작성일: 2025-10-22
> 작성자: Security Review Team
> **⚠️ 위험도: 높음 - 즉시 조치 필요**

## 목차
- [긴급 보안 이슈](#긴급-보안-이슈)
- [시크릿 및 ENV 관리 현황](#시크릿-및-env-관리-현황)
- [개선 권장사항](#개선-권장사항)
- [계정 및 레지스트리 권한 정리](#계정-및-레지스트리-권한-정리)
- [보안 체크리스트](#보안-체크리스트)

---

## 긴급 보안 이슈

### 🔴 Critical - 하드코딩된 Credential

#### 1. Keycloak Admin 비밀번호 노출

**위치**: `common/keycloak-values.yaml`

```yaml
auth:
  adminUser: cnAdmin
  adminPassword: <KEYCLOAK_ADMIN_PASSWORD>  # ⚠️ EXPOSED
```

**위험도**: 🔴 **Critical**

**영향**:
- Keycloak 전체 관리자 권한 탈취 가능
- 모든 사용자 계정 접근 가능
- 인증 시스템 완전 장악 가능
- OAuth2 토큰 조작 가능

**노출 범위**:
- GitHub Public Repository (확인 필요)
- Git History에 영구 기록
- 협업자 누구나 접근 가능

---

#### 2. Keycloak Database 비밀번호 노출

**위치**: `common/keycloak-values.yaml`

```yaml
externalDatabase:
  host: postgresql.default.svc.cluster.local
  port: 5432
  user: keycloak
  password: <KEYCLOAK_DB_PASSWORD>  # ⚠️ EXPOSED
  database: keycloak
```

**위험도**: 🔴 **Critical**

**영향**:
- Keycloak 데이터베이스 직접 접근
- 사용자 정보 유출 (해시된 비밀번호 포함)
- 데이터 변조/삭제 가능

---

#### 3. PostgreSQL Admin 비밀번호 노출

**위치**: `common/postgresql/values.yaml`

```yaml
auth:
  postgresPassword: <POSTGRES_ADMIN_PASSWORD>  # ⚠️ EXPOSED
  username: postgres
  password: <POSTGRES_ADMIN_PASSWORD>  # ⚠️ EXPOSED
  database: caring_note
```

**위험도**: 🔴 **Critical**

**영향**:
- 전체 데이터베이스 슈퍼유저 권한
- 모든 데이터베이스 접근 (caring_note, caring_note_staging, keycloak)
- 데이터 전체 유출/삭제 가능
- 백도어 생성 가능

---

#### 4. Backend Keycloak Admin Credential 노출

**위치**: `caring-note-api-server/src/main/resources/application.yml`

```yaml
keycloak:
  url: https://caringnote.co.kr/keycloak/
  realm: caringnote
  admin-username: cnAdmin
  admin-password: <KEYCLOAK_ADMIN_PASSWORD>  # ⚠️ EXPOSED
```

**위험도**: 🔴 **Critical**

**영향**:
- Backend에서 Keycloak API 전체 접근 권한
- 프로그래매틱하게 사용자 생성/삭제 가능
- Realm 설정 변경 가능

---


## 개선 권장사항

### 즉시 조치 필요 (24-48시간 내)

#### 1. 노출된 비밀번호 변경

**작업 순서**:

```bash
# 1. 새 비밀번호 생성
NEW_KEYCLOAK_ADMIN_PWD=$(openssl rand -base64 32)
NEW_POSTGRES_PWD=$(openssl rand -base64 32)
NEW_KEYCLOAK_DB_PWD=$(openssl rand -base64 32)

# 2. PostgreSQL 비밀번호 변경
kubectl exec -it postgresql-0 -- psql -U postgres
ALTER USER postgres WITH PASSWORD '<new-password>';
ALTER USER keycloak WITH PASSWORD '<new-keycloak-db-password>';
\q

# 3. Keycloak admin 비밀번호 변경
# Keycloak Admin Console에서 수동 변경
# 또는 kcadm.sh 사용

# 4. Kubernetes Secret 업데이트
kubectl create secret generic api-secret \
  --from-literal=SPRING_DATASOURCE_PASSWORD=<new-password> \
  --from-literal=... \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Deployment 재시작
kubectl rollout restart deployment/caring-note-api
kubectl rollout restart deployment/keycloak
```

**점검 사항**:
- [ ] PostgreSQL 비밀번호 변경 완료
- [ ] Keycloak admin 비밀번호 변경 완료
- [ ] Keycloak DB user 비밀번호 변경 완료
- [ ] Kubernetes Secrets 업데이트
- [ ] 모든 서비스 정상 작동 확인
- [ ] 이전 비밀번호로 접근 불가 확인

---

#### 2. Git에서 Credential 제거

**⚠️ 중요**: Git history에 이미 커밋된 비밀번호는 영구 기록됩니다!

**방법 1: BFG Repo-Cleaner (권장)**

```bash
# 1. BFG 다운로드
wget https://repo1.maven.org/maven2/com/madgag/bfg/1.14.0/bfg-1.14.0.jar

# 2. 민감 정보 파일 목록 작성 (passwords.txt)
<KEYCLOAK_ADMIN_PASSWORD>
<POSTGRES_ADMIN_PASSWORD>
<KEYCLOAK_DB_PASSWORD>

# 3. Git history에서 제거
java -jar bfg-1.14.0.jar --replace-text passwords.txt caring-note-deployment/.git

# 4. Git gc 실행
cd caring-note-deployment
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# 5. Force push (⚠️ 팀원과 조율 필요)
git push --force --all
git push --force --tags
```

**방법 2: git-filter-repo (권장)**

```bash
# 1. git-filter-repo 설치
pip3 install git-filter-repo

# 2. 민감 파일 제거
cd caring-note-deployment
git filter-repo --path common/keycloak-values.yaml --invert-paths
git filter-repo --path common/postgresql/values.yaml --invert-paths

# 3. 새로운 파일로 재작성 (비밀번호 제거 버전)
git add common/keycloak-values.yaml
git add common/postgresql/values.yaml
git commit -m "security: Remove hardcoded passwords"

# 4. Force push
git push --force
```

**⚠️ Force Push 주의사항**:
- 모든 팀원에게 사전 공지
- 팀원들은 로컬 저장소를 새로 클론해야 함
- CI/CD 캐시 삭제 필요
- 백업 후 진행

**대안**: History 정리가 어렵다면
- Repository를 private으로 변경
- 새 repository 생성 후 마이그레이션
- 비밀번호 변경만 먼저 진행 (이미 노출되었으므로 history 정리는 추후)

---

#### 3. 하드코딩된 Credential을 Secret으로 마이그레이션

**Keycloak values.yaml 수정**:

```yaml
# Before
auth:
  adminUser: cnAdmin
  adminPassword: <KEYCLOAK_ADMIN_PASSWORD>  # ❌

# After
auth:
  adminUser: cnAdmin
  existingSecret: keycloak-admin-secret  # ✅
  existingSecretPasswordKey: admin-password

externalDatabase:
  existingSecret: keycloak-db-secret  # ✅
  existingSecretPasswordKey: password
```

**Secret 생성**:

```bash
# Keycloak admin secret
kubectl create secret generic keycloak-admin-secret \
  --from-literal=admin-password='<STRONG-RANDOM-PASSWORD>' \
  -n default

# Keycloak DB secret
kubectl create secret generic keycloak-db-secret \
  --from-literal=password='<STRONG-RANDOM-PASSWORD>' \
  -n default

# PostgreSQL secret
kubectl create secret generic postgresql-secret \
  --from-literal=postgres-password='<STRONG-RANDOM-PASSWORD>' \
  --from-literal=password='<STRONG-RANDOM-PASSWORD>' \
  -n default
```

**PostgreSQL values.yaml 수정**:

```yaml
# Before
auth:
  postgresPassword: <POSTGRES_ADMIN_PASSWORD>  # ❌
  password: <POSTGRES_ADMIN_PASSWORD>  # ❌

# After
auth:
  existingSecret: postgresql-secret  # ✅
```

**Backend application.yml 수정**:

```yaml
# Before
keycloak:
  admin-username: cnAdmin
  admin-password: <KEYCLOAK_ADMIN_PASSWORD>  # ❌

# After
keycloak:
  admin-username: ${KEYCLOAK_ADMIN_USERNAME}
  admin-password: ${KEYCLOAK_ADMIN_PASSWORD}  # ✅ 환경 변수로
```

**Deployment에 환경 변수 추가**:

```yaml
env:
  - name: KEYCLOAK_ADMIN_USERNAME
    valueFrom:
      secretKeyRef:
        name: keycloak-admin-secret
        key: admin-username
  - name: KEYCLOAK_ADMIN_PASSWORD
    valueFrom:
      secretKeyRef:
        name: keycloak-admin-secret
        key: admin-password
```

---

### 단기 개선 (1-2주)

#### 옵션 1: Sealed Secrets (권장)

**Sealed Secrets란?**
- Bitnami에서 개발한 Kubernetes Secret 암호화 도구
- Public key로 암호화된 "SealedSecret"을 Git에 안전하게 저장
- 클러스터의 Private key로만 복호화 가능

**장점**:
- ✅ GitOps 친화적 (암호화된 Secret을 Git에 커밋)
- ✅ 설치 및 사용 간단
- ✅ 비용 없음 (오픈소스)
- ✅ Kubernetes 네이티브

**설치**:

```bash
# Controller 설치
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# CLI 설치 (kubeseal)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

**사용법**:

```bash
# 1. 일반 Secret 생성 (로컬에서만, Git에 커밋 안 함)
kubectl create secret generic api-secret \
  --from-literal=SPRING_DATASOURCE_PASSWORD='<password>' \
  --from-literal=OPEN_AI_API_KEY='<key>' \
  --dry-run=client -o yaml > api-secret.yaml

# 2. SealedSecret으로 암호화
kubeseal -f api-secret.yaml -w api-sealed-secret.yaml

# 3. 암호화된 파일을 Git에 커밋
git add api-sealed-secret.yaml
git commit -m "Add sealed secret for API"

# 4. 클러스터에 적용
kubectl apply -f api-sealed-secret.yaml

# 5. Sealed Secret controller가 자동으로 복호화하여 Secret 생성
kubectl get secrets api-secret  # 자동 생성됨
```

**디렉토리 구조**:

```
common/
  secrets/
    api-secret-sealed.yaml          # ✅ Git에 커밋
    api-secret-staging-sealed.yaml  # ✅ Git에 커밋
    keycloak-admin-sealed.yaml      # ✅ Git에 커밋
    postgresql-sealed.yaml          # ✅ Git에 커밋
  README.md  # Secret 생성 방법 문서화
```

**주의사항**:
- Controller의 private key를 반드시 백업
- Key 손실 시 모든 SealedSecret 복호화 불가
- 정기적인 key rotation 계획 수립

---

#### 옵션 2: External Secrets Operator + Cloud Secret Manager

**External Secrets Operator란?**
- 외부 Secret 저장소와 Kubernetes를 동기화
- AWS Secrets Manager, GCP Secret Manager, Azure Key Vault 등 지원

**장점**:
- ✅ 중앙화된 Secret 관리
- ✅ 클라우드 네이티브 암호화
- ✅ 자동 로테이션 지원
- ✅ 감사 로그

**단점**:
- ❌ 추가 비용 (Cloud Secret Manager)
- ❌ 클라우드 종속성
- ❌ 복잡도 증가

**예상 비용** (AWS Secrets Manager):
- Secret 저장: $0.40/secret/month
- API 호출: $0.05/10,000 calls
- 예상 총 비용: ~$5/month (10개 secret 기준)

**구조**:

```
┌─────────────────────────────────────────┐
│  AWS Secrets Manager                    │
│  ├─ caring-note/api/db-password        │
│  ├─ caring-note/api/openai-key         │
│  └─ caring-note/keycloak/admin-pwd     │
└─────────────────┬───────────────────────┘
                  │
                  │ (External Secrets Operator)
                  ↓
┌─────────────────────────────────────────┐
│  Kubernetes Cluster                     │
│  ├─ Secret: api-secret (auto-synced)   │
│  ├─ Secret: keycloak-admin (auto-sync) │
│  └─ Secret: postgresql (auto-synced)   │
└─────────────────────────────────────────┘
```

**현 상황에서는 Sealed Secrets 권장** (비용 및 복잡도 고려)

---

#### 옵션 3: HashiCorp Vault (고급)

**장점**:
- ✅ 동적 Secret 생성
- ✅ TTL 기반 자동 만료
- ✅ 세밀한 권한 관리
- ✅ 감사 로그

**단점**:
- ❌ 운영 복잡도 매우 높음
- ❌ 추가 인프라 필요 (Vault cluster)
- ❌ 학습 곡선 steep

**권장**: 대규모 조직 또는 엔터프라이즈 요구사항이 있을 때만

---

### 중기 개선 (1-3개월)

#### 1. 네트워크 정책 활성화

**현재 상태**:
- NetworkPolicy 파일 존재하지만 미사용

**활성화 계획**:

```yaml
# PostgreSQL Network Policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgresql-netpol
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
  - Ingress
  ingress:
  # API에서만 접근 허용
  - from:
    - podSelector:
        matchLabels:
          app: caring-note-api
    ports:
    - protocol: TCP
      port: 5432

  # Keycloak에서만 접근 허용
  - from:
    - podSelector:
        matchLabels:
          app: keycloak
    ports:
    - protocol: TCP
      port: 5432

---
# Keycloak Network Policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: keycloak-netpol
spec:
  podSelector:
    matchLabels:
      app: keycloak
  policyTypes:
  - Ingress
  ingress:
  # Ingress Controller에서만 접근 허용
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
```

---

#### 2. Pod Security Standards 적용

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: default
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Pod Security Context 강화**:

```yaml
# Deployment에 추가
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault

      containers:
      - name: caring-note-api
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true  # 가능한 경우
          capabilities:
            drop:
            - ALL
```

---

#### 3. 리소스 제한 (Security 관점)

```yaml
resources:
  limits:
    memory: "1Gi"
    cpu: "1000m"
    ephemeral-storage: "2Gi"  # ⭐ 임시 스토리지 제한
  requests:
    memory: "512Mi"
    cpu: "250m"
    ephemeral-storage: "500Mi"
```

**목적**:
- DoS 공격 완화
- Resource exhaustion 방지
- 노드 안정성 확보

---

#### 4. Secrets Scanning (CI/CD에 추가)

**Gitleaks 도입**:

```yaml
# .github/workflows/secret-scan.yml
name: Secret Scan

on: [push, pull_request]

jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
      with:
        fetch-depth: 0

    - name: Gitleaks Scan
      uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**pre-commit hook 추가**:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

---

## 계정 및 레지스트리 권한 정리

### Docker Hub (bsh998 계정)

**현재 상태**:
- 계정: `bsh998`
- 이미지:
  - `bsh998/caring-note-api`
  - `bsh998/caring-note-web`
  - `bsh998/caring-note-keycloak`

**권장 조치**:

1. **Access Token 사용**
   ```bash
   # 비밀번호 대신 Read/Write Token 생성
   # Docker Hub > Account Settings > Security > New Access Token

   # GitHub Secrets 업데이트
   DOCKERHUB_TOKEN=<generated-token>  # 비밀번호 대신
   ```

2. **Organization 전환 검토**
   ```
   개인 계정 (bsh998) → Organization (caringnote-org)

   장점:
   - 팀 단위 권한 관리
   - 소유권 분산
   - 감사 로그
   ```

3. **이미지 Vulnerability Scanning**
   ```bash
   # Docker Hub에서 자동 스캔 활성화
   # 또는 Trivy 사용

   docker run aquasec/trivy image bsh998/caring-note-api:latest
   ```

4. **Image Signing (선택)**
   ```bash
   # Docker Content Trust 활성화
   export DOCKER_CONTENT_TRUST=1
   docker push bsh998/caring-note-api:latest
   ```

---

### GitHub Repository 권한

**현재 상태**:
- 4개 Repository (api-server, web, deployment, keycloak-theme)
- Branch protection (main, staging)

**권장 조치**:

1. **Branch Protection 강화**
   ```
   Settings > Branches > Branch protection rules

   For 'main' and 'staging':
   ✅ Require pull request reviews (최소 1명)
   ✅ Dismiss stale PR approvals
   ✅ Require status checks (CI tests)
   ✅ Require branches to be up to date
   ✅ Include administrators (예외 없음)
   ✅ Restrict force pushes
   ✅ Restrict deletions
   ```

2. **Secrets 접근 권한**
   ```
   Settings > Secrets and variables > Actions

   권장:
   - Organization secrets 사용 (가능 시)
   - Environment-specific secrets (Production, Staging)
   - Required reviewers for production deployments
   ```

3. **Team & Collaborator 정리**
   ```
   Settings > Collaborators and teams

   역할 분리:
   - Admin: 1-2명 (최소한)
   - Write: 개발자
   - Read: QA, PM
   ```

---

### Kakao Cloud VM 접근

**현재 상태**:
- SSH 접근: GitHub Secrets의 `VM_SSH_KEY`
- kubectl 권한: VM 내부에서 unrestricted

**권장 조치**:

1. **SSH Key Rotation**
   ```bash
   # 정기적 SSH key 변경 (3-6개월)
   ssh-keygen -t ed25519 -C "caringnote-ci@example.com"

   # 새 key를 GitHub Secrets에 업데이트
   ```

2. **RBAC 적용** (Kubernetes)
   ```yaml
   # CI/CD 전용 ServiceAccount 생성
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: github-actions-deployer
     namespace: default

   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     name: deployment-manager
   rules:
   - apiGroups: ["apps"]
     resources: ["deployments"]
     verbs: ["get", "list", "update", "patch"]
   - apiGroups: [""]
     resources: ["pods", "pods/log"]
     verbs: ["get", "list"]

   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     name: github-actions-deployer-binding
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: Role
     name: deployment-manager
   subjects:
   - kind: ServiceAccount
     name: github-actions-deployer
   ```

3. **Bastion Host 도입 검토**
   ```
   현재: GitHub Actions → SSH → VM

   개선: GitHub Actions → Bastion → VM

   장점:
   - 접근 기록 중앙화
   - MFA 적용 가능
   - IP whitelist 관리
   ```

---

### Keycloak Realm 권한

**현재 상태**:
- Admin 계정: `cnAdmin`
- 권한: Realm admin (전체 권한)

**권장 조치**:

1. **역할 분리**
   ```
   Realm: caringnote

   Users:
   - keycloak-admin (슈퍼 관리자, 비상용)
   - api-service-account (Backend에서 사용, 제한된 권한)
   - user-manager (사용자 관리만, UI 접근용)

   Roles:
   - manage-users
   - view-users
   - manage-clients
   - view-events
   ```

2. **Service Account 사용**
   ```java
   // Backend에서 admin 계정 대신 service account 사용

   Keycloak Client:
   - Client ID: caring-note-backend
   - Access Type: confidential
   - Service Accounts Enabled: true
   - Assigned Roles: manage-users (필요 시)
   ```

3. **MFA 활성화**
   ```
   Admin Console 접근 시 OTP 필수
   ```

---

## 보안 체크리스트

### 즉시 조치 (Critical)

- [ ] Keycloak admin 비밀번호 변경
- [ ] PostgreSQL admin 비밀번호 변경
- [ ] Keycloak DB user 비밀번호 변경
- [ ] Kubernetes Secrets 업데이트
- [ ] 모든 서비스 정상 작동 확인

### 1주 내 (High)

- [ ] Git history에서 credential 제거 (또는 repository를 private으로)
- [ ] 하드코딩된 비밀번호를 Secret으로 마이그레이션
- [ ] application.yml에서 keycloak admin 정보 제거
- [ ] Sealed Secrets 도입 검토 및 설치
- [ ] Docker Hub Access Token 전환

### 2주 내 (Medium)

- [ ] CORS 설정 Profile별 분리
- [ ] GitHub Branch Protection 강화
- [ ] Secrets Scanning (Gitleaks) 도입
- [ ] SSH Key rotation
- [ ] Keycloak 역할 분리

### 1개월 내 (Low)

- [ ] Network Policy 활성화
- [ ] Pod Security Standards 적용
- [ ] Resource limits 설정
- [ ] Kubernetes RBAC 적용
- [ ] Vulnerability scanning 자동화

### 지속적 (Ongoing)

- [ ] 정기 보안 점검 (월 1회)
- [ ] Secret rotation (3-6개월)
- [ ] 접근 로그 리뷰
- [ ] 보안 패치 적용
- [ ] 침투 테스트 (연 1회)

---

## 참고 자료

- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/#best-practices)
- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

---

**문서 버전**: 1.0
**심각도**: 🔴 Critical
**다음 리뷰 예정일**: 매주 검토 (조치 완료 시까지)
