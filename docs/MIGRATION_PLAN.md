# 인프라 개선 마이그레이션 계획

> 작성일: 2025-11-05
> 최종 수정: 2026-04-09
> 상태: ✅ Phase 1~2 완료 / 📋 Phase 3 선택 적용
> 예상 기간: 5주 (Phase 1~2 완료됨)

## 목차
- [개요](#개요)
- [현재 상태 분석](#현재-상태-분석)
- [목표 아키텍처](#목표-아키텍처)
- [Phase 1: VM 분리](#phase-1-vm-분리)
- [Phase 2: Sentry 적용](#phase-2-sentry-적용)
- [Phase 3: Slack 알림 적용 (선택 적용)](#phase-3-slack-알림-적용-선택-적용)
- [마이그레이션 체크리스트](#마이그레이션-체크리스트)
- [리스크 관리](#리스크-관리)
- [예상 비용](#예상-비용)

---

## 개요

### 목적
1. **환경 격리**: Staging과 Production 환경을 물리적으로 완전 분리
2. **고가용성**: 단일 VM 장애 시 영향 범위 최소화
3. **가시성**: 에러 추적 및 알림 시스템 도입
4. **안정성**: 독립 데이터베이스로 환경 간 간섭 방지

### 주요 개선 사항
- ✅ Staging 전용 VM 분리 **(완료)**
- ✅ Sentry 에러 추적 시스템 도입 **(완료)**
- 📋 Slack 배포/에러 알림 통합 **(선택 — 필요 시 적용)**
- 📋 리소스 제한 설정 **(선택 — 필요 시 적용)**

---

## 현재 상태 분석

### 현재 아키텍처

```
┌─────────────────────────────────────────────────────┐
│  Kakao Cloud VM (t1i.xlarge)                        │
│  IP: [Production IP]                                │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  Single Node Kubernetes Cluster                │ │
│  │                                                 │ │
│  │  Namespace: default (Production)                │ │
│  │  ├── caring-note-api (replica: 1)              │ │
│  │  ├── caring-note-web (replica: 1)              │ │
│  │  ├── PostgreSQL (16.4.0)                       │ │
│  │  │   ├── DB: caring_note                       │ │
│  │  │   └── DB: caring_note_staging               │ │
│  │  └── Keycloak (26.0.6)                         │ │
│  │                                                 │ │
│  │  Namespace: caring-note-staging                 │ │
│  │  ├── caring-note-api (replica: 1)              │ │
│  │  └── caring-note-web (replica: 1)              │ │
│  │      └── 공유: PostgreSQL, Keycloak             │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  Ingress (Nginx)                                     │
│  ├── caringnote.co.kr → default/caring-note-*       │
│  └── stage.caringnote.co.kr → staging/caring-note-*   │
└─────────────────────────────────────────────────────┘
```

### 문제점

| 항목 | 문제 | 영향도 |
|------|------|--------|
| **SPOF** | 단일 VM 장애 시 모든 환경 중단 | 🔴 높음 |
| **리소스 경쟁** | Staging 테스트가 Production에 영향 가능 | 🟡 중간 |
| **DB 공유** | PostgreSQL/Keycloak 공유로 격리 불완전 | 🟡 중간 |
| **모니터링 부재** | 에러 추적 시스템 없음 | 🟡 중간 |
| **알림 부재** | 배포/에러 알림 수동 확인 | 🟢 낮음 |

---

## 목표 아키텍처

### 개선 후 구조

```
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│  Staging VM (t1i.large)         │  │  Production VM (t1i.xlarge)     │
│  IP: [New Staging IP]           │  │  IP: [Existing Production IP]   │
│                                  │  │                                  │
│  ┌────────────────────────────┐ │  │  ┌────────────────────────────┐ │
│  │  K8s Single Node           │ │  │  │  K8s Single Node           │ │
│  │                             │ │  │  │                             │ │
│  │  Namespace: default         │ │  │  │  Namespace: default         │ │
│  │  ├── API (SPRING_PROFILES  │ │  │  │  ├── API (SPRING_PROFILES  │ │
│  │  │   =staging)              │ │  │  │  │   =prod)                │ │
│  │  ├── Web                    │ │  │  │  ├── Web                    │ │
│  │  ├── PostgreSQL (독립)      │ │  │  │  ├── PostgreSQL (독립)      │ │
│  │  │   └── caring_note_staging│ │  │  │   └── caring_note          │ │
│  │  └── Keycloak (독립)        │ │  │  │  └── Keycloak (독립)        │ │
│  └────────────────────────────┘ │  │  └────────────────────────────┘ │
│                                  │  │                                  │
│  Ingress: stage.caringnote.co.kr  │  │  Ingress: caringnote.co.kr      │
└─────────────────────────────────┘  └─────────────────────────────────┘
         │                                      │
         └──────────────┬───────────────────────┘
                        │
                ┌───────▼────────┐
                │  Sentry Cloud  │
                │  ├─ Staging    │
                │  └─ Production │
                └───────┬────────┘
                        │
                ┌───────▼────────┐
                │  Slack Channel │
                │  #caringnote   │
                └────────────────┘
```

### 주요 변경 사항

| 구분 | 변경 전 | 변경 후 |
|------|---------|---------|
| **VM 수** | 1대 | 2대 (Staging/Production 분리) |
| **PostgreSQL** | 공유 (2 DB) | 각각 독립 인스턴스 |
| **Keycloak** | 공유 | 각각 독립 인스턴스 |
| **에러 추적** | 없음 | Sentry (무료 플랜) |
| **알림** | 없음 | Slack 통합 |
| **리소스 제한** | 미설정 | CPU/Memory limits 설정 |

---

## Phase 1: VM 분리

### 목표
Staging 환경을 별도 VM으로 완전 분리

### 예상 기간
**2-3주**

---

### Task 1.1: Staging VM 프로비저닝 (1일)

#### 작업 내용
1. Kakao Cloud Console에서 새 VM 인스턴스 생성
2. 기본 설정

#### 상세 단계

```bash
# 1. Kakao Cloud Console
# - Instance 생성
# - Name: caring-note-staging-vm
# - Type: t1i.large (2 vCPU, 8GB RAM)
# - Storage: 512GB SSD
# - Network: 기존 VPC와 동일
# - Security Group: HTTP(80), HTTPS(443), SSH(22) 허용

# 2. SSH 접속 테스트
ssh -i <key.pem> ubuntu@<STAGING_VM_IP>

# 3. 기본 패키지 업데이트
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git vim

# 4. Docker 설치
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

#### 체크리스트
- [x] VM 인스턴스 생성 완료
- [x] SSH 접속 확인
- [x] Docker 설치 및 동작 확인
- [x] 보안 그룹 설정 완료

---

### Task 1.2: Kubernetes 클러스터 설치 (2-3일)

#### 작업 내용
단일 노드 K8s 클러스터 구성 (Production과 동일 방식)

#### 상세 단계

```bash
# 1. Kubernetes 설치 (kubeadm 방식 - Production과 동일)
# 설치 스크립트는 기존 Production VM과 동일하게 사용

# 예시 (실제 스크립트는 프로젝트에 맞게 조정)
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 2. 클러스터 초기화
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# 3. kubectl 설정
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 4. CNI 플러그인 설치 (Flannel 예시)
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# 5. 단일 노드 클러스터이므로 master taint 제거
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 6. 클러스터 상태 확인
kubectl get nodes
kubectl get pods -A
```

#### 체크리스트
- [x] K8s 클러스터 초기화 완료
- [x] CNI 플러그인 설치 완료
- [x] 노드 Ready 상태 확인
- [x] System pods 정상 동작 확인

---

### Task 1.3: Helm 및 기본 컴포넌트 설치 (1일)

#### 작업 내용
Nginx Ingress, cert-manager 설치

#### 상세 단계

```bash
# 1. Git clone
git clone https://github.com/MediBird/caring-note-deployment.git
cd caring-note-deployment

# 2. Helm 설치
./common/get_helm.sh

# 3. 기본 환경 설정 (nginx-ingress, cert-manager 등)
./common/helm_list.sh

# 4. ClusterIssuer 적용 (Let's Encrypt)
kubectl apply -f common/cluster-issuer.yaml

# 5. 설치 확인
helm list -A
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
```

#### 체크리스트
- [x] Helm 설치 완료
- [x] Nginx Ingress Controller 설치 완료
- [x] cert-manager 설치 완료
- [x] ClusterIssuer 생성 완료

---

### Task 1.4: PostgreSQL 독립 배포 (1일)

#### 작업 내용
Staging 전용 PostgreSQL 인스턴스 배포

#### 상세 단계

```bash
# 1. PV 생성 (Staging용)
# pvc/postgresql-pv-staging.yaml 생성 필요 (새 파일)
kubectl apply -f pvc/postgresql-pv-staging.yaml

# 2. PostgreSQL values 수정
# common/postgresql/values-staging.yaml 생성 (복사 후 수정)
cp common/postgresql/values.yaml common/postgresql/values-staging.yaml

# 수정 사항:
# - auth.database: caring_note_staging
# - primary.persistence.existingClaim: postgresql-pvc-staging
# - 비밀번호는 Secret으로 관리 (SECURITY.md 참조)

# 3. PostgreSQL Helm 설치
helm install postgresql-staging ./common/postgresql -f common/postgresql/values-staging.yaml

# 4. 설치 확인
kubectl get pods | grep postgresql
kubectl get pvc

# 5. DB 접속 테스트
kubectl exec -it postgresql-staging-0 -- psql -U postgres -d caring_note_staging
```

#### 체크리스트
- [x] PV/PVC 생성 완료
- [x] PostgreSQL Helm 배포 완료
- [x] Pod 정상 동작 확인
- [x] DB 접속 테스트 완료

---

### Task 1.5: Keycloak 독립 배포 (1일)

#### 작업 내용
Staging 전용 Keycloak 인스턴스 배포

#### 상세 단계

```bash
# 1. Keycloak values 수정
# common/keycloak-values-staging.yaml 생성
cp common/keycloak-values.yaml common/keycloak-values-staging.yaml

# 수정 사항:
# - externalDatabase.host: postgresql-staging.default.svc.cluster.local
# - externalDatabase.database: keycloak_staging
# - auth: Secret 참조로 변경 (SECURITY.md 참조)

# 2. Keycloak DB 생성
kubectl exec -it postgresql-staging-0 -- psql -U postgres
CREATE DATABASE keycloak_staging;
CREATE USER keycloak_staging WITH PASSWORD '<password>';
GRANT ALL PRIVILEGES ON DATABASE keycloak_staging TO keycloak_staging;
\q

# 3. Keycloak Helm 설치
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install keycloak-staging bitnami/keycloak -f common/keycloak-values-staging.yaml

# 4. 설치 확인
kubectl get pods | grep keycloak
kubectl logs keycloak-staging-0

# 5. Keycloak Admin Console 접속 테스트
# http://<STAGING_VM_IP>/keycloak (또는 Ingress 설정 후)
```

#### 체크리스트
- [x] Keycloak DB 생성 완료
- [x] Keycloak Helm 배포 완료
- [x] Pod 정상 동작 확인
- [x] Admin Console 접속 확인

---

### Task 1.6: Staging API/Web 배포 (1일)

#### 작업 내용
Staging 환경에 API/Web 애플리케이션 배포

#### 상세 단계

```bash
# 1. Kubernetes Secret 생성 (Staging용)
kubectl create secret generic api-secret-staging \
  --from-literal=SPRING_DATASOURCE_USERNAME=postgres \
  --from-literal=SPRING_DATASOURCE_PASSWORD='<password>' \
  --from-literal=OPEN_AI_API_KEY='<key>' \
  --from-literal=CLOVA_API_KEY='<key>' \
  -n default

# 2. Staging manifest 수정
# staging/*.yaml에서 namespace 제거 (이제 default 사용)
# 또는 namespace를 그대로 두고 namespace 생성

# 3. 배포
kubectl apply -f staging/api.yaml
kubectl apply -f staging/web.yaml
kubectl apply -f staging/ingress.yaml

# 4. 배포 확인
kubectl get deployments
kubectl get pods
kubectl get svc
kubectl get ingress

# 5. 로그 확인
kubectl logs -f deployment/caring-note-api
```

#### 체크리스트
- [x] Secret 생성 완료
- [x] API Deployment 배포 완료
- [x] Web Deployment 배포 완료
- [x] Ingress 설정 완료
- [x] Pod 정상 동작 확인

---

### Task 1.7: DNS 및 SSL 설정 (1일)

#### 작업 내용
stage.caringnote.co.kr DNS 변경 및 SSL 인증서 발급

#### 상세 단계

```bash
# 1. DNS 레코드 변경 (DNS 관리 콘솔에서)
# stage.caringnote.co.kr A Record: <NEW_STAGING_VM_IP>

# 2. DNS 전파 확인
nslookup stage.caringnote.co.kr
dig stage.caringnote.co.kr

# 3. Ingress에서 cert-manager annotation 확인
kubectl describe ingress caring-note-ingress -n default

# annotations:
#   cert-manager.io/cluster-issuer: "letsencrypt-prod"

# 4. Certificate 생성 확인
kubectl get certificate
kubectl describe certificate caring-note-tls

# 5. SSL 인증서 발급 대기 (수 분 소요)
kubectl get certificate -w

# 6. HTTPS 접속 테스트
curl -I https://stage.caringnote.co.kr
```

#### 체크리스트
- [x] DNS A Record 변경 완료
- [x] DNS 전파 확인
- [x] Let's Encrypt Certificate 발급 완료
- [x] HTTPS 접속 테스트 성공
- [x] 브라우저에서 정상 접속 확인

---

### Task 1.8: DB 데이터 마이그레이션 (1일)

#### 작업 내용
기존 Production VM의 caring_note_staging DB를 새 Staging VM으로 이전

#### 상세 단계

```bash
# 1. Production VM에서 Staging DB 백업
# SSH to Production VM
kubectl exec -it postgresql-0 -- pg_dump -U postgres caring_note_staging > caring_note_staging_backup.sql

# 2. 백업 파일을 로컬로 다운로드
scp ubuntu@<PROD_VM_IP>:~/caring_note_staging_backup.sql .

# 3. Staging VM으로 업로드
scp caring_note_staging_backup.sql ubuntu@<STAGING_VM_IP>:~/

# 4. Staging VM에서 복원
# SSH to Staging VM
kubectl cp caring_note_staging_backup.sql postgresql-staging-0:/tmp/
kubectl exec -it postgresql-staging-0 -- psql -U postgres caring_note_staging < /tmp/caring_note_staging_backup.sql

# 5. 데이터 확인
kubectl exec -it postgresql-staging-0 -- psql -U postgres caring_note_staging
\dt
SELECT COUNT(*) FROM <main_table>;
\q

# 6. 백업 파일 삭제 (보안)
rm caring_note_staging_backup.sql
ssh ubuntu@<STAGING_VM_IP> "rm ~/caring_note_staging_backup.sql"
ssh ubuntu@<PROD_VM_IP> "rm ~/caring_note_staging_backup.sql"
```

#### 체크리스트
- [x] DB 백업 완료
- [x] 백업 파일 다운로드/업로드 완료
- [x] DB 복원 완료
- [x] 데이터 정합성 확인
- [x] 백업 파일 삭제 완료

---

### Task 1.9: CI/CD 파이프라인 수정 (1일)

#### 작업 내용
GitHub Actions에서 Staging 배포 대상을 새 VM으로 변경

#### 상세 단계

```yaml
# 1. GitHub Secrets 추가
# Settings > Secrets > Actions
# - STAGING_VM_HOST: <NEW_STAGING_VM_IP>
# - STAGING_VM_SSH_KEY: <new_staging_ssh_key>
# - STAGING_VM_USER: ubuntu

# 2. .github/workflows/deploy-staging.yml 수정 (API/Web 레포지토리에서)
# 기존:
# - host: ${{ secrets.VM_HOST }}
#
# 변경:
# - host: ${{ secrets.STAGING_VM_HOST }}
# - key: ${{ secrets.STAGING_VM_SSH_KEY }}

# 3. 배포 테스트
# staging 브랜치에 테스트 커밋 push
git checkout staging
git commit --allow-empty -m "test: CI/CD pipeline to new Staging VM"
git push origin staging

# 4. GitHub Actions 로그 확인
# - 빌드 성공 여부
# - 새 Staging VM에 배포 확인

# 5. 배포 결과 확인
# SSH to Staging VM
kubectl get pods
kubectl logs deployment/caring-note-api
```

#### 체크리스트
- [x] GitHub Secrets 추가 완료
- [x] Workflow 파일 수정 완료
- [x] Staging 브랜치 배포 테스트 성공
- [x] 새 VM에 Pod 업데이트 확인
- [x] 애플리케이션 정상 동작 확인

---

### Task 1.10: Production VM 정리 (0.5일)

#### 작업 내용
Production VM에서 Staging 리소스 제거

#### 상세 단계

```bash
# SSH to Production VM

# 1. Staging namespace 리소스 확인
kubectl get all -n caring-note-staging

# 2. Staging 리소스 삭제
kubectl delete -f staging/api.yaml
kubectl delete -f staging/web.yaml
kubectl delete -f staging/ingress.yaml

# 3. Namespace 삭제
kubectl delete namespace caring-note-staging

# 4. PostgreSQL에서 Staging DB 삭제 (선택)
kubectl exec -it postgresql-0 -- psql -U postgres
DROP DATABASE caring_note_staging;
\q

# 5. 리소스 정리 확인
kubectl get all -n caring-note-staging  # 오류 발생하면 정상
kubectl get pods
```

#### 체크리스트
- [x] Staging Deployment/Service 삭제 완료
- [x] Staging Namespace 삭제 완료
- [x] Staging DB 삭제 (선택) 완료
- [x] Production 리소스만 남아있는지 확인

---

### Phase 1 최종 검증 체크리스트

#### 인프라 검증
- [x] Staging VM: K8s 클러스터 정상 동작
- [x] Production VM: 기존과 동일하게 정상 동작
- [x] DNS: stage.caringnote.co.kr → Staging VM
- [x] DNS: caringnote.co.kr → Production VM
- [x] SSL: 양쪽 모두 Let's Encrypt 인증서 정상

#### 애플리케이션 검증
- [x] Staging: API Health Check 정상
- [x] Staging: Web 페이지 로드 정상
- [x] Staging: Keycloak 로그인 정상
- [x] Staging: DB CRUD 테스트 정상
- [x] Production: 기존과 동일하게 정상 동작

#### CI/CD 검증
- [x] staging 브랜치 push → Staging VM 배포 정상
- [x] main 브랜치 push → Production VM 배포 정상
- [x] Docker 이미지 태그 자동 업데이트 정상

---

## Phase 2: Sentry 적용

### 목표
에러 추적 시스템 도입으로 실시간 에러 모니터링

### 예상 기간
**1주**

---

### Task 2.1: Sentry 프로젝트 생성 (0.5일)

#### 작업 내용
Sentry 계정 생성 및 프로젝트 설정

#### 상세 단계

```bash
# 1. Sentry 계정 생성
# https://sentry.io 접속
# - 무료 플랜 선택 (월 5,000 이벤트)
# - Organization 생성: caringnote

# 2. 프로젝트 생성 (2개)
# Project 1: caring-note-production
#   - Platform: Spring Boot
#   - DSN 복사 및 저장

# Project 2: caring-note-staging
#   - Platform: Spring Boot
#   - DSN 복사 및 저장

# 3. Frontend 프로젝트 생성 (2개)
# Project 3: caring-note-web-production
#   - Platform: React
#   - DSN 복사 및 저장

# Project 4: caring-note-web-staging
#   - Platform: React
#   - DSN 복사 및 저장

# 4. Alert 설정
# Settings > Alerts > New Alert Rule
# - Error rate > 10/hour → Email 알림
```

#### 체크리스트
- [x] Sentry 계정 생성 완료
- [x] Backend 프로젝트 2개 생성 (Staging/Production)
- [x] Frontend 프로젝트 2개 생성 (Staging/Production)
- [x] DSN 키 4개 안전하게 저장
- [x] Alert Rule 설정 완료

---

### Task 2.2: Backend Sentry 통합 (1일)

#### 작업 내용
Spring Boot 애플리케이션에 Sentry SDK 추가

#### 상세 단계

**1. API 레포지토리에서 작업**

```gradle
// build.gradle 수정
dependencies {
    implementation 'io.sentry:sentry-spring-boot-starter:7.0.0'
    implementation 'io.sentry:sentry-logback:7.0.0'
}
```

```yaml
# src/main/resources/application.yml
sentry:
  dsn: ${SENTRY_DSN}
  environment: ${SPRING_PROFILES_ACTIVE}
  traces-sample-rate: 0.1  # 10% 트랜잭션 추적
  enable-tracing: true
  release: ${SENTRY_RELEASE:unknown}

  # 민감 정보 제외
  in-app-includes:
    - com.caringnote

  # Exception 필터링 (404 등 제외)
  ignored-exceptions-for-type:
    - org.springframework.web.servlet.NoHandlerFoundException
```

```xml
<!-- src/main/resources/logback-spring.xml 수정 -->
<configuration>
    <appender name="SENTRY" class="io.sentry.logback.SentryAppender">
        <filter class="ch.qos.logback.classic.filter.ThresholdFilter">
            <level>ERROR</level>
        </filter>
    </appender>

    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
        <appender-ref ref="SENTRY"/>
    </root>
</configuration>
```

**2. Kubernetes Secret에 DSN 추가**

```bash
# Staging VM
kubectl create secret generic api-secret-staging \
  --from-literal=SENTRY_DSN='<staging-dsn>' \
  --dry-run=client -o yaml | kubectl apply -f -

# Production VM
kubectl create secret generic api-secret \
  --from-literal=SENTRY_DSN='<production-dsn>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

**3. Deployment에 환경 변수 추가**

```yaml
# prod/api.yaml, staging/api.yaml 수정
env:
  - name: SENTRY_DSN
    valueFrom:
      secretKeyRef:
        name: api-secret  # staging은 api-secret-staging
        key: SENTRY_DSN
  - name: SENTRY_RELEASE
    value: "${IMAGE_TAG}"  # Git commit SHA
```

**4. 테스트**

```java
// 테스트용 Exception 발생시키기
@RestController
public class TestController {
    @GetMapping("/test/sentry")
    public String testSentry() {
        throw new RuntimeException("Sentry test error!");
    }
}
```

```bash
# 배포
git commit -am "feat: Add Sentry integration"
git push origin staging

# 배포 후 테스트
curl https://stage.caringnote.co.kr/api/test/sentry

# Sentry 대시보드에서 에러 확인
```

#### 체크리스트
- [x] build.gradle 의존성 추가 완료
- [x] application.yml Sentry 설정 완료
- [x] logback Sentry appender 추가 완료
- [x] Kubernetes Secret에 DSN 추가 완료
- [x] Deployment manifest 수정 완료
- [x] Staging 배포 및 테스트 완료
- [x] Sentry 대시보드에서 에러 확인 완료
- [x] Production 배포 완료

---

### Task 2.3: Frontend Sentry 통합 (1일)

#### 작업 내용
React 애플리케이션에 Sentry SDK 추가

#### 상세 단계

**1. Web 레포지토리에서 작업**

```bash
# 패키지 설치
npm install --save @sentry/react
```

```javascript
// src/index.js (또는 App.js)
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: process.env.REACT_APP_SENTRY_DSN,
  environment: process.env.REACT_APP_ENV || "production",
  release: process.env.REACT_APP_VERSION,

  integrations: [
    new Sentry.BrowserTracing(),
    new Sentry.Replay({
      maskAllText: false,
      blockAllMedia: false,
    }),
  ],

  // Performance 모니터링
  tracesSampleRate: 0.1,

  // Session Replay
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,

  // 민감 정보 필터링
  beforeSend(event, hint) {
    // PII 제거
    if (event.request) {
      delete event.request.cookies;
    }
    return event;
  },
});

// ErrorBoundary 사용
function App() {
  return (
    <Sentry.ErrorBoundary fallback={<ErrorFallback />}>
      <YourApp />
    </Sentry.ErrorBoundary>
  );
}
```

**2. .env 파일 설정**

```bash
# .env.staging
REACT_APP_SENTRY_DSN=<staging-web-dsn>
REACT_APP_ENV=staging
REACT_APP_VERSION=${GITHUB_SHA}

# .env.production
REACT_APP_SENTRY_DSN=<production-web-dsn>
REACT_APP_ENV=production
REACT_APP_VERSION=${GITHUB_SHA}
```

**3. CI/CD에서 환경 변수 주입**

```yaml
# .github/workflows/deploy-web-staging.yml
- name: Build Docker Image
  run: |
    docker build \
      --build-arg REACT_APP_SENTRY_DSN=${{ secrets.SENTRY_WEB_DSN_STAGING }} \
      --build-arg REACT_APP_ENV=staging \
      --build-arg REACT_APP_VERSION=${{ github.sha }} \
      -t bsh998/caring-note-web:${{ github.sha }} .
```

**4. 테스트**

```javascript
// 테스트용 에러 발생 버튼
<button onClick={() => {
  throw new Error("Sentry frontend test!");
}}>
  Test Sentry
</button>
```

```bash
# 배포 및 테스트
git commit -am "feat: Add Sentry to frontend"
git push origin staging

# 브라우저에서 버튼 클릭 → Sentry 확인
```

#### 체크리스트
- [ ] @sentry/react 패키지 설치 완료
- [ ] Sentry.init() 설정 완료
- [ ] ErrorBoundary 적용 완료
- [ ] .env 파일 설정 완료
- [ ] CI/CD build-arg 추가 완료
- [ ] Staging 배포 및 테스트 완료
- [ ] Sentry 대시보드에서 에러 확인 완료
- [ ] Production 배포 완료

---

### Task 2.4: Sentry Release 추적 설정 (0.5일)

#### 작업 내용
Git commit SHA를 Sentry release로 연동하여 배포 추적

#### 상세 단계

```bash
# 1. Sentry CLI 설치 (CI/CD Runner에서)
# .github/workflows/deploy-api-staging.yml

- name: Create Sentry Release
  env:
    SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
    SENTRY_ORG: caringnote
    SENTRY_PROJECT: caring-note-staging
  run: |
    # Sentry CLI 설치
    curl -sL https://sentry.io/get-cli/ | bash

    # Release 생성
    sentry-cli releases new ${{ github.sha }}

    # Commits 연동
    sentry-cli releases set-commits ${{ github.sha }} --auto

    # Deploy 표시
    sentry-cli releases deploys ${{ github.sha }} new -e staging

    # Release finalize
    sentry-cli releases finalize ${{ github.sha }}

# 2. GitHub Secrets 추가
# SENTRY_AUTH_TOKEN: Sentry > Settings > Auth Tokens > New Token
```

#### 체크리스트
- [ ] Sentry Auth Token 생성 완료
- [ ] GitHub Secrets에 토큰 추가 완료
- [ ] CI/CD에 Release 생성 스텝 추가 완료
- [ ] Staging 배포 시 Release 자동 생성 확인
- [ ] Sentry에서 Release 목록 확인
- [ ] Production workflow에도 동일 설정 완료

---

### Phase 2 최종 검증 체크리스트

#### Sentry 통합 검증
- [x] Backend Error가 Sentry에 자동 전송됨
- [ ] Frontend Error가 Sentry에 자동 전송됨 — 미적용
- [x] Staging/Production 프로젝트 분리 확인
- [ ] Release 정보가 Git commit과 연동됨 — 미적용
- [x] Alert Email 수신 테스트 완료

#### 에러 추적 테스트
- [x] 의도적 Exception 발생 → Sentry 캡처 확인
- [x] Stack trace 정보 정확성 확인
- [x] User context 정보 확인 (IP, Browser 등)
- [x] Breadcrumbs 확인 (에러 발생 전 이벤트)

---

## Phase 3: Slack 알림 적용 (선택 적용)

> **📋 참고**: Phase 3는 필수가 아닌 선택 사항입니다. 팀 규모나 운영 필요에 따라 적용 여부를 판단하세요.

### 목표
배포 및 에러 알림을 Slack으로 통합

### 예상 기간
**3-5일**

---

### Task 3.1: Slack Workspace 설정 (0.5일)

#### 작업 내용
Slack 채널 생성 및 Webhook 설정

#### 상세 단계

```bash
# 1. Slack Workspace 접속
# caringnote.slack.com (또는 기존 Workspace)

# 2. 채널 생성
# #caringnote-deploy: 배포 알림 전용
# #caringnote-errors: 에러 알림 전용

# 3. Incoming Webhook 앱 추가
# Slack > Apps > Browse Apps > Incoming Webhooks > Add to Slack

# 4. Webhook URL 생성 (2개)
# - #caringnote-deploy 채널용 Webhook URL
# - #caringnote-errors 채널용 Webhook URL

# 5. Webhook URL 저장
# GitHub Secrets에 추가 예정
```

#### 체크리스트
- [ ] Slack 채널 2개 생성 완료
- [ ] Incoming Webhook 앱 설치 완료
- [ ] Webhook URL 2개 생성 완료
- [ ] Webhook URL 안전하게 저장

---

### Task 3.2: GitHub Actions → Slack 알림 (1일)

#### 작업 내용
CI/CD 배포 성공/실패 시 Slack 알림

#### 상세 단계

```yaml
# .github/workflows/deploy-api-staging.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      # ... 기존 배포 스텝들 ...

      - name: Slack Notification - Start
        uses: 8398a7/action-slack@v3
        with:
          status: custom
          custom_payload: |
            {
              "text": "🚀 Deployment Started",
              "attachments": [{
                "color": "warning",
                "fields": [
                  {
                    "title": "Environment",
                    "value": "Staging",
                    "short": true
                  },
                  {
                    "title": "Branch",
                    "value": "${{ github.ref_name }}",
                    "short": true
                  },
                  {
                    "title": "Commit",
                    "value": "<https://github.com/${{ github.repository }}/commit/${{ github.sha }}|${{ github.sha }}>",
                    "short": false
                  },
                  {
                    "title": "Author",
                    "value": "${{ github.actor }}",
                    "short": true
                  }
                ]
              }]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_DEPLOY }}

      # ... 배포 실행 ...

      - name: Slack Notification - Success
        if: success()
        uses: 8398a7/action-slack@v3
        with:
          status: custom
          custom_payload: |
            {
              "text": "✅ Deployment Successful",
              "attachments": [{
                "color": "good",
                "fields": [
                  {
                    "title": "Environment",
                    "value": "Staging",
                    "short": true
                  },
                  {
                    "title": "URL",
                    "value": "https://stage.caringnote.co.kr",
                    "short": true
                  },
                  {
                    "title": "Deployed At",
                    "value": "${{ steps.date.outputs.date }}",
                    "short": false
                  }
                ]
              }]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_DEPLOY }}

      - name: Slack Notification - Failure
        if: failure()
        uses: 8398a7/action-slack@v3
        with:
          status: custom
          custom_payload: |
            {
              "text": "❌ Deployment Failed",
              "attachments": [{
                "color": "danger",
                "fields": [
                  {
                    "title": "Environment",
                    "value": "Staging",
                    "short": true
                  },
                  {
                    "title": "Job URL",
                    "value": "<https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Logs>",
                    "short": false
                  }
                ]
              }]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_DEPLOY }}

# GitHub Secrets 추가
# SLACK_WEBHOOK_DEPLOY: <deploy-channel-webhook-url>
# SLACK_WEBHOOK_ERRORS: <errors-channel-webhook-url>
```

#### 체크리스트
- [ ] GitHub Secrets에 Webhook URL 추가 완료
- [ ] Workflow에 Slack 알림 스텝 추가 완료
- [ ] Staging 배포 테스트 → Slack 알림 확인
- [ ] Success/Failure 케이스 모두 테스트
- [ ] Production workflow에도 동일 설정 완료
- [ ] Web 레포지토리에도 동일 설정 완료

---

### Task 3.3: Sentry → Slack 연동 (0.5일)

#### 작업 내용
Sentry 에러 발생 시 Slack 알림

#### 상세 단계

```bash
# 1. Sentry 프로젝트 설정
# Sentry > Settings > Integrations > Slack

# 2. Slack Workspace 연동
# - caringnote Workspace 선택
# - 권한 승인

# 3. Alert Rule 생성 (각 프로젝트마다)
# Settings > Alerts > New Alert Rule

# Alert 1: High Error Rate
# - When: An event is seen
# - If: event.level equals error
# - Then: Send a notification via Slack
# - Channel: #caringnote-errors

# Alert 2: New Issue
# - When: A new issue is created
# - Then: Send a notification via Slack
# - Channel: #caringnote-errors

# Alert 3: Issue Spike
# - When: The issue changes state from resolved to unresolved
# - Then: Send a notification via Slack
# - Channel: #caringnote-errors

# 4. 알림 포맷 커스터마이징
# - Issue title
# - Environment (staging/production)
# - Error message
# - Stack trace preview
# - Link to Sentry
```

#### 체크리스트
- [ ] Sentry Slack Integration 설치 완료
- [ ] Workspace 연동 완료
- [ ] Alert Rule 3개 생성 (각 프로젝트)
- [ ] Staging에서 테스트 에러 발생 → Slack 확인
- [ ] Production Alert도 동일하게 설정 완료

---

### Task 3.4: Backend 직접 Slack 알림 (선택, 1일)

#### 작업 내용
중요 이벤트 발생 시 Backend에서 직접 Slack 알림 전송

#### 상세 단계

```java
// SlackNotifier.java
@Component
public class SlackNotifier {

    @Value("${slack.webhook.url}")
    private String webhookUrl;

    private final RestTemplate restTemplate = new RestTemplate();

    public void sendMessage(String message, String color) {
        Map<String, Object> payload = Map.of(
            "text", message,
            "attachments", List.of(
                Map.of("color", color)
            )
        );

        try {
            restTemplate.postForEntity(webhookUrl, payload, String.class);
        } catch (Exception e) {
            log.error("Failed to send Slack notification", e);
        }
    }

    public void sendError(String title, String message) {
        sendMessage("🚨 " + title + "\n" + message, "danger");
    }

    public void sendWarning(String title, String message) {
        sendMessage("⚠️ " + title + "\n" + message, "warning");
    }

    public void sendInfo(String title, String message) {
        sendMessage("ℹ️ " + title + "\n" + message, "good");
    }
}

// 사용 예시
@RestControllerAdvice
public class GlobalExceptionHandler {

    @Autowired
    private SlackNotifier slackNotifier;

    @ExceptionHandler(CriticalException.class)
    public ResponseEntity<?> handleCriticalException(CriticalException e) {
        slackNotifier.sendError(
            "Critical Error in Production",
            "Error: " + e.getMessage() + "\nUser: " + getCurrentUser()
        );
        return ResponseEntity.status(500).body("Internal Server Error");
    }
}
```

```yaml
# application.yml
slack:
  webhook:
    url: ${SLACK_WEBHOOK_ERRORS}
```

```yaml
# Deployment에 환경 변수 추가
env:
  - name: SLACK_WEBHOOK_ERRORS
    valueFrom:
      secretKeyRef:
        name: api-secret
        key: SLACK_WEBHOOK_ERRORS
```

#### 체크리스트
- [ ] SlackNotifier 컴포넌트 구현 완료
- [ ] application.yml 설정 추가 완료
- [ ] Kubernetes Secret에 Webhook URL 추가 완료
- [ ] GlobalExceptionHandler 연동 완료
- [ ] 테스트 에러 발생 → Slack 확인

---

### Phase 3 최종 검증 체크리스트

#### Slack 통합 검증
- [ ] 배포 시작 시 Slack 알림 수신
- [ ] 배포 성공 시 Slack 알림 수신
- [ ] 배포 실패 시 Slack 알림 수신
- [ ] Sentry 에러 발생 시 Slack 알림 수신
- [ ] Backend 직접 알림 (선택) 수신

#### 알림 내용 검증
- [ ] Environment (Staging/Production) 구분 명확
- [ ] Commit SHA 및 Link 포함
- [ ] 배포자 정보 포함
- [ ] 에러 메시지 및 Stack trace 포함
- [ ] Sentry Link 포함

---

## 마이그레이션 체크리스트

### 사전 준비
- [x] 프로젝트 이해관계자 공유 및 승인
- [x] 다운타임 허용 시간 협의
- [x] 백업 계획 수립
- [x] 롤백 계획 수립

### Phase 1: VM 분리 ✅ 완료
- [x] 1.1: Staging VM 프로비저닝 (1일)
- [x] 1.2: Kubernetes 클러스터 설치 (2-3일)
- [x] 1.3: Helm 및 기본 컴포넌트 설치 (1일)
- [x] 1.4: PostgreSQL 독립 배포 (1일)
- [x] 1.5: Keycloak 독립 배포 (1일)
- [x] 1.6: Staging API/Web 배포 (1일)
- [x] 1.7: DNS 및 SSL 설정 (1일)
- [x] 1.8: DB 데이터 마이그레이션 (1일)
- [x] 1.9: CI/CD 파이프라인 수정 (1일)
- [x] 1.10: Production VM 정리 (0.5일)
- [x] Phase 1 최종 검증

### Phase 2: Sentry 적용 ✅ 완료 (Backend만)
- [x] 2.1: Sentry 프로젝트 생성 (0.5일)
- [x] 2.2: Backend Sentry 통합 (1일)
- [ ] 2.3: Frontend Sentry 통합 (1일) — 미적용
- [ ] 2.4: Sentry Release 추적 설정 (0.5일) — 미적용
- [x] Phase 2 최종 검증 (Backend)

### Phase 3: Slack 알림 적용 📋 선택 적용 (필요 시 진행)
- [ ] 3.1: Slack Workspace 설정 (0.5일)
- [ ] 3.2: GitHub Actions → Slack 알림 (1일)
- [ ] 3.3: Sentry → Slack 연동 (0.5일)
- [ ] 3.4: Backend 직접 Slack 알림 (선택, 1일)
- [ ] Phase 3 최종 검증

### 최종 검증
- [ ] 전체 배포 플로우 End-to-End 테스트
- [ ] 성능 테스트 (리소스 사용량, 응답 시간)
- [ ] 보안 점검 (SECURITY.md 참조)
- [ ] 문서 업데이트
- [ ] 팀 교육 및 인수인계

---

## 리스크 관리

### 고위험 리스크

| 리스크 | 영향 | 확률 | 대응 방안 |
|--------|------|------|-----------|
| **DB 마이그레이션 실패** | 🔴 높음 | 🟡 중간 | - 백업 3중화 (로컬/S3/다른 VM)<br>- 복원 테스트 사전 실시<br>- 롤백 스크립트 준비 |
| **DNS 전환 다운타임** | 🟡 중간 | 🟢 낮음 | - TTL 미리 60초로 단축<br>- 점진적 전환 (일부 트래픽 먼저)<br>- Health check 자동화 |
| **CI/CD 파이프라인 오류** | 🟡 중간 | 🟡 중간 | - Staging에서 충분히 테스트<br>- Rollback 명령어 사전 준비<br>- 수동 배포 가능하도록 대기 |

### 중위험 리스크

| 리스크 | 영향 | 확률 | 대응 방안 |
|--------|------|------|-----------|
| **SSL 인증서 발급 실패** | 🟡 중간 | 🟢 낮음 | - Self-signed 인증서 임시 사용<br>- cert-manager 로그 모니터링<br>- Let's Encrypt Rate Limit 확인 |
| **Sentry 통합 오류** | 🟢 낮음 | 🟡 중간 | - 비필수 기능이므로 점진적 적용<br>- 로컬 로그는 그대로 유지<br>- DSN 검증 도구 사용 |
| **Slack 알림 누락** | 🟢 낮음 | 🟢 낮음 | - 중복 알림 채널 (Email + Slack)<br>- Webhook URL 유효성 테스트 |

---

## 예상 비용

### 인프라 비용

| 항목 | 현재 | 개선 후 | 월 증가분 |
|------|------|---------|----------|
| **Production VM** | t1i.xlarge<br>₩80,000/월 | t1i.xlarge<br>₩80,000/월 | - |
| **Staging VM** | - | t1i.large<br>₩50,000/월 | **₩50,000** |
| **Storage** | 1TB SSD | 1TB + 512GB SSD | ~₩10,000 |
| **네트워크** | 기존 | 기존 | - |
| **소계** | ₩80,000/월 | ₩140,000/월 | **₩60,000/월** |

### 소프트웨어 비용

| 항목 | 플랜 | 월 비용 |
|------|------|---------|
| **Sentry** | Free (5,000 events/month) | 무료 |
| **Slack** | Free | 무료 |
| **소계** | - | **무료** |

### 총 예상 비용

- **월 증가분**: ₩60,000
- **연 증가분**: ₩720,000

### 비용 최적화 방안

1. **Staging VM 스펙 조정** (선택)
   - t1i.large → t1i.medium (필요 시)
   - 절감: ~₩20,000/월

2. **Sentry 이벤트 제한**
   - 무료 플랜 5,000 events 초과 시
   - 샘플링 비율 조정 (0.1 → 0.05)

3. **야간 Staging VM 중지** (선택)
   - 야간/주말 자동 중지
   - 절감: ~₩20,000/월

---

## 후속 조치

### 즉시 조치 (마이그레이션 완료 후 1주)
- [ ] 리소스 제한 설정
- [ ] 모니터링 대시보드 구성
- [ ] 알림 임계값 튜닝
- [ ] 팀 교육 자료 작성

### 단기 조치 (1개월)
- [ ] 백업 자동화 스크립트 작성
- [ ] Disaster Recovery 절차 문서화
- [ ] 정기 보안 점검 스케줄 수립
- [ ] 비용 모니터링 및 최적화

### 중기 조치 (3개월)
- [ ] Prometheus + Grafana 도입 검토
- [ ] 로그 중앙화 시스템 검토
- [ ] Auto-scaling 검토 (트래픽 증가 시)
- [ ] Multi-region 확장 검토 (필요 시)

---

## 참고 문서

- [SECURITY.md](./SECURITY.md) - 보안 및 권한 관리
- [Sentry Documentation](https://docs.sentry.io/)
- [Slack API Documentation](https://api.slack.com/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

---

**문서 버전**: 1.0
**작성일**: 2025-11-05
**다음 업데이트**: 진행 상황에 따라 수시 업데이트
