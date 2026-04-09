# 데이터베이스 설정 가이드

## 데이터베이스 초기 설정

PostgreSQL 설치 후 API 서버를 위한 데이터베이스 스키마를 설정하는 방법입니다.

### 1. schema.sql 파일 준비

API 서버 프로젝트에서 `schema.sql` 파일을 생성합니다:
```bash
# caring-note-api-server 프로젝트 루트에 schema.sql 파일이 있어야 함
```

### 2. PostgreSQL Pod에 schema.sql 파일 복사

**Production 환경:**
```bash
# 로컬에서 VM으로 복사
scp -i ~/.ssh/key-caring-note.pem schema.sql ubuntu@<PRODUCTION_VM_IP>:/home/ubuntu/

# VM에서 PostgreSQL Pod으로 복사
kubectl cp /home/ubuntu/schema.sql default/postgresql-0:/tmp/schema.sql
```

**Staging 환경:**
```bash
# 로컬에서 VM으로 복사
scp -i ~/.ssh/key-caring-note-stage.pem schema.sql ubuntu@<STAGING_VM_IP>:/home/ubuntu/

# VM에서 PostgreSQL Pod으로 복사
kubectl cp /home/ubuntu/schema.sql caring-note-staging/postgresql-0:/tmp/schema.sql
```

### 3. PostgreSQL 스키마 초기화 및 권한 설정

PostgreSQL Pod에 접속하여 스키마를 초기화합니다:

```bash
# PostgreSQL Pod 접속
kubectl exec -it -n caring-note-staging postgresql-0 -- bash
# Production: kubectl exec -it -n default postgresql-0 -- bash
```

Pod 내부에서 다음 단계를 실행:

**3-1. postgres 유저로 스키마 초기화**
```bash
# PostgreSQL 접속 (비밀번호 입력 프롬프트 사용)
psql -U postgres -d caring_note -W

# psql 프롬프트에서 실행
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO caringnote;
GRANT ALL ON SCHEMA public TO public;
\q
```

**3-2. caringnote 유저로 스키마 생성**
```bash
# caringnote 유저로 PostgreSQL 접속
psql -U caringnote -d caring_note -W
# 비밀번호: caringNote2024!! (Staging) 또는 Secret에서 확인

# psql 프롬프트에서 schema.sql 실행
\i /tmp/schema.sql

# 테이블 생성 확인 (17개 테이블이 생성되어야 함)
\dt

# 종료
\q
exit
```

### 4. 테이블 생성 확인

```bash
# VM에서 테이블 목록 확인
kubectl exec -n caring-note-staging postgresql-0 -- \
  psql -U caringnote -d caring_note -W -c "\dt"
```

예상 결과: 17개 테이블 (counselors, counselees, counsel_sessions, counsel_cards, medications, 등)

### 주의사항

- **테이블 소유자**: 테이블은 반드시 `caringnote` 유저로 생성해야 합니다. API 서버가 `caringnote` 유저로 접속하기 때문입니다.
- **권한 문제**: 만약 `postgres` 유저로 테이블을 생성했다면, `caringnote` 유저에게 권한을 부여해야 합니다:
  ```sql
  -- postgres 유저로 실행
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO caringnote;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO caringnote;
  ```

---

## 운영 DB 스키마를 스테이징으로 이관

운영 환경의 실제 스키마를 스테이징 환경으로 복제하는 방법입니다. JPA 엔티티와 실제 DB 스키마의 불일치를 방지할 수 있습니다.

### 1. 운영 DB에서 스키마 덤프

**운영 VM에 SSH 접속:**
```bash
ssh -i ~/.ssh/key-caring-note.pem ubuntu@<PRODUCTION_VM_IP>
```

**PostgreSQL Pod 접속:**
```bash
kubectl exec -it -n default postgresql-0 -- bash
```

**스키마 덤프 생성 (데이터 제외):**
```bash
# Pod 내부에서 실행
pg_dump -U postgres -d caring_note --schema-only --no-owner --no-privileges -f /tmp/prod_schema.sql

# 덤프 파일 확인
ls -lh /tmp/prod_schema.sql
head -50 /tmp/prod_schema.sql

# Pod에서 나오기
exit
```

**VM으로 파일 복사:**
```bash
# 운영 VM에서 실행
kubectl cp default/postgresql-0:/tmp/prod_schema.sql /tmp/prod_schema.sql
```

### 2. 로컬(Windows)로 파일 전송

**로컬 PowerShell에서 실행:**
```powershell
# 운영 VM → 로컬
scp -i $env:USERPROFILE\.ssh\key-caring-note.pem ubuntu@<PRODUCTION_VM_IP>:/tmp/prod_schema.sql $env:USERPROFILE\Downloads\prod_schema.sql

# 로컬 → 스테이징 VM
scp -i $env:USERPROFILE\.ssh\key-caring-note-stage.pem $env:USERPROFILE\Downloads\prod_schema.sql ubuntu@210.109.53.166:/tmp/
```

### 3. 스테이징 DB에 스키마 적용

**스테이징 VM에 SSH 접속:**
```bash
ssh -i ~/.ssh/key-caring-note-stage.pem ubuntu@210.109.53.166
```

**PostgreSQL Pod으로 파일 복사:**
```bash
kubectl cp /tmp/prod_schema.sql caring-note-staging/postgresql-0:/tmp/prod_schema.sql
```

**PostgreSQL Pod 접속:**
```bash
kubectl exec -it -n caring-note-staging postgresql-0 -- bash
```

**스키마 초기화 (postgres 유저):**
```bash
psql -U postgres -d caring_note -W
```

psql 프롬프트에서:
```sql
-- 기존 스키마 완전 삭제 (테이블, 제약조건 등 모두 삭제)
DROP SCHEMA public CASCADE;

-- 새 스키마 생성
CREATE SCHEMA public;

-- caringnote 유저에게 권한 부여
GRANT ALL ON SCHEMA public TO caringnote;
GRANT ALL ON SCHEMA public TO public;

-- 확인 (아무것도 없어야 함)
\dt

\q
```

**운영 스키마 적용 (caringnote 유저):**
```bash
psql -U caringnote -d caring_note -W
# 비밀번호: caringNote2024!! (또는 Secret에서 확인)
```

psql 프롬프트에서:
```sql
-- 스키마 파일 실행
\i /tmp/prod_schema.sql

-- 테이블 생성 확인
\dt public.*

-- 특정 테이블 구조 확인
\d public.counselors
\d public.counsel_cards

\q
```

**search_path 영구 설정 (중요!):**
```bash
# postgres 유저로 접속
psql -U postgres -d caring_note -W
```

psql 프롬프트에서:
```sql
-- caringnote 유저의 기본 search_path 설정
ALTER ROLE caringnote SET search_path TO public;

-- 데이터베이스 기본값도 설정
ALTER DATABASE caring_note SET search_path TO public;

\q
exit
```

**설정 확인:**
```bash
# caringnote 유저로 다시 접속
kubectl exec -it -n caring-note-staging postgresql-0 -- bash
psql -U caringnote -d caring_note -W
```

psql 프롬프트에서:
```sql
-- 이제 자동으로 public 스키마 접근 가능
\dt
SELECT * FROM counselors LIMIT 1;
\q
exit
```

### 4. API 재시작 및 확인

```bash
# API Pod 재시작
kubectl rollout restart deployment/caring-note-api -n caring-note-staging

# 재시작 상태 확인
kubectl rollout status deployment/caring-note-api -n caring-note-staging

# API 로그 확인 (에러 없어야 함)
kubectl logs -n caring-note-staging deployment/caring-note-api --tail=100

# 테이블 에러 확인
kubectl logs -n caring-note-staging deployment/caring-note-api --tail=200 | grep -i "error\|exception\|table\|relation"
```

### 주의사항

- **search_path 설정 필수**: `ALTER ROLE caringnote SET search_path TO public;`를 실행하지 않으면 API가 테이블을 찾지 못합니다.
- **스키마 소유자**: 운영 스키마는 `--no-owner` 옵션으로 덤프했기 때문에 `caringnote` 유저로 실행하면 자동으로 `caringnote` 소유가 됩니다.
- **CASCADE 옵션**: `DROP SCHEMA public CASCADE`는 모든 테이블, 제약조건, 인덱스를 완전히 삭제합니다.
- **데이터 마이그레이션**: 이 방법은 스키마만 복사하며, 데이터는 포함되지 않습니다. 데이터가 필요하면 `pg_dump`에서 `--schema-only` 옵션을 제거하세요.
