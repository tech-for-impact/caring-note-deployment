# TLS Certificate 설정 가이드

> CaringNote Staging/Production 환경의 HTTPS 인증서 설정

## 📋 목차
- [TLS Secret 이해하기](#tls-secret-이해하기)
- [Production 환경 TLS](#production-환경-tls)
- [Staging 환경 TLS 설정](#staging-환경-tls-설정)
- [문제 해결](#문제-해결)

---

## TLS Secret 이해하기

### 1. `caringnote-tls` (애플리케이션 TLS)

**용도**: 외부 사용자가 HTTPS로 접속할 때 사용하는 SSL 인증서

**내용**:
```bash
kubectl get secret caringnote-tls -n default -o yaml
```

```yaml
data:
  tls.crt: <Base64 인코딩된 인증서>
  tls.key: <Base64 인코딩된 개인키>
```

**발급 기관**: Let's Encrypt (무료 SSL 인증서)

**발급 방식**: cert-manager가 자동으로 발급 및 갱신

**적용 위치**:
- `prod/ingress.yaml` → `tls.secretName: caringnote-tls`
- `staging/ingress.yaml` → `tls.secretName: caringnote-tls-staging`

---

### 2. `ingress-nginx-release-admission` (내부 Webhook TLS)

**용도**: Ingress Nginx Controller의 Admission Webhook 통신용 인증서

**발급 방식**: Ingress Nginx Helm 설치 시 자동 생성 (Self-Signed)

**특징**:
- 외부 사용자와 무관
- Kubernetes 내부 통신용
- 수동 관리 불필요

**내용**:
```yaml
data:
  ca: <인증서 CA>
  cert: <인증서>
  key: <개인키>
```

---

## Production 환경 TLS

### 현재 상태

**도메인**: `caringnote.co.kr`

**인증서**: Let's Encrypt에서 발급됨

**Secret 이름**: `caringnote-tls`

**발급 확인**:
```bash
# Production VM에서
kubectl get certificate -n default
kubectl describe certificate caringnote-tls

# Secret 확인
kubectl get secret caringnote-tls -n default
```

**인증서 정보 확인**:
```bash
kubectl get secret caringnote-tls -n default -o json | \
  jq -r '.data."tls.crt"' | base64 -d | openssl x509 -text -noout
```

출력 예시:
```
Issuer: C = US, O = Let's Encrypt, CN = R13
Subject: CN = caringnote.co.kr
Not Before: Sep 20 06:19:59 2025 GMT
Not After : Dec 19 06:19:58 2025 GMT (약 3개월)
```

---

## Staging 환경 TLS 설정

### 사전 준비

#### 1. DNS 설정

Staging VM의 Public IP 확인:
```bash
# Staging VM에서
curl ifconfig.me
```

DNS 레코드 추가 (Kakao Cloud DNS 또는 도메인 관리 페이지):
```
Type: A
Name: stage.caringnote.co.kr
Value: <Staging VM Public IP>
TTL: 300
```

DNS 전파 확인:
```bash
# 로컬에서
nslookup stage.caringnote.co.kr
dig stage.caringnote.co.kr
```

---

### 자동 발급 (cert-manager 사용) - 권장

Staging 환경에서는 이미 `staging/ingress.yaml`에 cert-manager 설정이 포함되어 있습니다.

#### 1. Ingress 확인

`staging/ingress.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: caringnote-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # ✅ cert-manager 자동 발급
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - stage.caringnote.co.kr
    secretName: caringnote-tls-staging  # ✅ 자동으로 생성될 Secret 이름
  rules:
  - host: stage.caringnote.co.kr
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: caring-note-api
            port:
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: caring-note-web
            port:
              number: 80
```

#### 2. Ingress 배포

```bash
kubectl apply -f staging/ingress.yaml
```

#### 3. cert-manager가 자동으로 처리

cert-manager는 다음을 자동으로 수행합니다:

1. **Certificate 리소스 생성**
   ```bash
   kubectl get certificate -n default
   ```

   출력:
   ```
   NAME                      READY   SECRET                    AGE
   caringnote-tls-staging    True    caringnote-tls-staging    2m
   ```

2. **Let's Encrypt에 인증서 요청**
   - HTTP-01 Challenge 수행
   - `.well-known/acme-challenge/` 경로로 검증

3. **Secret 자동 생성**
   ```bash
   kubectl get secret caringnote-tls-staging -n default
   ```

#### 4. 발급 진행 상황 확인

```bash
# Certificate 상태 확인
kubectl describe certificate caringnote-tls-staging -n default

# CertificateRequest 확인
kubectl get certificaterequest -n default

# Challenge 확인 (문제 발생 시)
kubectl get challenge -n default
kubectl describe challenge <challenge-name>

# cert-manager 로그 확인
kubectl logs -n cert-manager -l app=cert-manager
```

**정상 발급 시**:
```
Status:
  Conditions:
    Type:    Ready
    Status:  True
    Message: Certificate is up to date and has not expired
```

**발급 실패 시**:
```
Status:
  Conditions:
    Type:    Ready
    Status:  False
    Reason:  Failed
    Message: <에러 메시지>
```

---

### 수동 발급 (필요 시)

cert-manager 없이 수동으로 Let's Encrypt 인증서를 발급하려면:

#### 1. certbot 설치

```bash
# Staging VM에서
sudo apt update
sudo apt install certbot -y
```

#### 2. 인증서 발급

```bash
sudo certbot certonly --standalone -d stage.caringnote.co.kr

# 또는 webroot 방식 (Nginx가 이미 실행 중인 경우)
sudo certbot certonly --webroot -w /var/www/html -d stage.caringnote.co.kr
```

#### 3. Kubernetes Secret 생성

```bash
sudo kubectl create secret tls caringnote-tls-staging \
  --cert=/etc/letsencrypt/live/stage.caringnote.co.kr/fullchain.pem \
  --key=/etc/letsencrypt/live/stage.caringnote.co.kr/privkey.pem \
  -n default
```

#### 4. 자동 갱신 설정

Let's Encrypt 인증서는 90일마다 만료되므로 자동 갱신 필요:

```bash
# cron job 추가
sudo crontab -e
```

```cron
# 매월 1일 오전 3시에 갱신
0 3 1 * * certbot renew --quiet --deploy-hook "kubectl create secret tls caringnote-tls-staging --cert=/etc/letsencrypt/live/stage.caringnote.co.kr/fullchain.pem --key=/etc/letsencrypt/live/stage.caringnote.co.kr/privkey.pem -n default --dry-run=client -o yaml | kubectl apply -f -"
```

---

## 인증서 갱신

### cert-manager 사용 시 (자동 갱신)

cert-manager는 만료 30일 전에 자동으로 갱신합니다.

수동 갱신:
```bash
# Certificate 삭제 후 재생성
kubectl delete certificate caringnote-tls-staging -n default

# Ingress 재적용으로 Certificate 재생성
kubectl apply -f staging/ingress.yaml
```

### 수동 발급 시

```bash
# certbot으로 갱신
sudo certbot renew

# Secret 업데이트
sudo kubectl create secret tls caringnote-tls-staging \
  --cert=/etc/letsencrypt/live/stage.caringnote.co.kr/fullchain.pem \
  --key=/etc/letsencrypt/live/stage.caringnote.co.kr/privkey.pem \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -

# Ingress 재로드
kubectl rollout restart deployment/caring-note-api -n default
kubectl rollout restart deployment/caring-note-web -n default
```

---

## 문제 해결

### 1. Certificate가 Ready되지 않음

**증상**:
```bash
kubectl get certificate
# READY 상태가 False
```

**원인 및 해결**:

#### DNS 미설정
```bash
# 확인
nslookup stage.caringnote.co.kr

# 해결: DNS A 레코드 추가 후 대기 (최대 24시간)
```

#### HTTP-01 Challenge 실패
```bash
# Challenge 확인
kubectl get challenge -n default
kubectl describe challenge <challenge-name>

# 방화벽 확인 (포트 80 오픈 필요)
sudo ufw status
curl http://stage.caringnote.co.kr/.well-known/acme-challenge/test
```

#### Rate Limit 초과
Let's Encrypt는 도메인당 주당 50개 인증서 발급 제한이 있습니다.

```bash
# 해결: Staging issuer 사용 (테스트용)
# common/cluster-issuer.yaml에서 letsencrypt-staging 사용
```

---

### 2. Secret은 있지만 HTTPS 접속 안 됨

**원인**:

#### Ingress TLS 설정 누락
```bash
kubectl describe ingress caringnote-ingress -n default

# tls 섹션 확인
```

#### Secret 이름 불일치
```bash
# Ingress의 tls.secretName과 실제 Secret 이름 확인
kubectl get ingress caringnote-ingress -o yaml | grep secretName
kubectl get secret -n default | grep tls
```

---

### 3. 인증서가 Self-Signed로 표시됨

**원인**: cert-manager가 아직 발급 중이거나 실패함

**확인**:
```bash
kubectl describe certificate caringnote-tls-staging

# Issuer 확인
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

**cert-manager Pod 재시작**:
```bash
kubectl rollout restart deployment/cert-manager -n cert-manager
```

---

### 4. 인증서 만료 확인

```bash
# Secret에서 인증서 추출 후 확인
kubectl get secret caringnote-tls-staging -n default -o json | \
  jq -r '.data."tls.crt"' | base64 -d | openssl x509 -noout -dates

# 출력:
# notBefore=Jan 11 00:00:00 2025 GMT
# notAfter=Apr 11 23:59:59 2025 GMT
```

만료 30일 전부터 갱신 권장.

---

## 요약

### Production
- **도메인**: `caringnote.co.kr`
- **Secret**: `caringnote-tls`
- **관리**: cert-manager 자동 갱신

### Staging
- **도메인**: `stage.caringnote.co.kr`
- **Secret**: `caringnote-tls-staging`
- **설정 순서**:
  1. DNS A 레코드 추가 (`stage.caringnote.co.kr` → Staging VM IP)
  2. `kubectl apply -f staging/ingress.yaml`
  3. cert-manager가 자동 발급 (2-5분 소요)
  4. `kubectl get certificate` 로 확인

---

**문서 버전**: 1.0
**최종 수정일**: 2025-01-11
