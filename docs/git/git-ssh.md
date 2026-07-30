# GitHub 개인·회사 계정 SSH 인증 정리

## 문제 상황

개인 저장소에서 `git pull`을 실행했을 때 다음 오류가 발생했다.

```text
remote: Repository not found.
fatal: repository 'https://github.com/crazywook/probe.git/' not found
```

당시 remote는 HTTPS였고, `gh`의 활성 계정은 회사 계정
`Alan-Supplies`였다. 저장소를 볼 권한이 없는 회사 계정의 인증 정보가
사용되면서 GitHub가 `Repository not found`를 반환했다.

## 혼동했던 개념

### `gh` 로그인과 Git 인증은 같지 않다

```text
gh 명령
→ gh 활성 계정 사용

HTTPS Git remote
→ credential helper 또는 token 사용

SSH Git remote
→ SSH 개인키 사용
```

현재 저장소는 SSH remote를 사용하므로 `gh`의 활성 계정이 회사 계정이어도
`git pull`과 `git push`에는 영향을 주지 않는다.

### `git@github.com`의 `git`은 GitHub 사용자명이 아니다

SSH 접속 주소는 모든 GitHub 계정이 동일하게 `git@github.com`을 사용한다.
GitHub는 접속할 때 제시된 SSH 공개키의 fingerprint를 보고 계정을 결정한다.

```text
SSH 클라이언트가 공개키 제시
→ GitHub가 fingerprint 확인
→ 공개키가 등록된 GitHub 계정 선택
→ 해당 계정의 저장소 권한 확인
```

### 커밋 작성자와 GitHub 인증 계정도 별개다

```text
git config user.name / user.email
→ 커밋에 기록되는 작성자

SSH key
→ pull/push 권한을 확인하는 GitHub 계정
```

## 확인된 SSH 키

이 Mac의 회사 계정용 RSA 키:

```text
파일: ~/.ssh/id_rsa
fingerprint: SHA256:2+zPrFEpTcsbEyPvcoj97DQEkjmXmD6o73h3DfidDdA
GitHub 계정: Alan-Supplies
```

이 Mac의 개인 계정용 Ed25519 키:

```text
파일: ~/.ssh/id_ed25519
fingerprint: SHA256:2JROi1VLZr4FBTgr0t0A2Z2W1EEuMFdYL6H1Eac8mbA
GitHub 계정: crazywook
```

Notion의 `git ssh` 페이지에 있던 RSA 공개키:

```text
fingerprint: SHA256:Ose/S5....
GitHub 계정: crazywook
```

Notion의 키는 GitHub에 기존 등록된 `crazywook` 공개키와 일치했지만,
이 Mac에서는 대응하는 개인키를 찾지 못했다. 공개키만으로는 인증할 수 없고,
대응하는 개인키가 반드시 필요하다.

현재는 이 Mac의 `~/.ssh/id_ed25519.pub`를 `crazywook` 계정에 추가해서
사용한다.

## 현재 저장소의 최종 인증 경로

```text
/Users/swkim/workspace/crazywook/probe
→ .git/config
→ remote.origin.url
→ git@github.com:crazywook/probe.git
→ core.sshCommand
→ ~/.ssh/id_ed25519
→ macOS SSH agent / Keychain
→ GitHub SSH key fingerprint
→ crazywook 계정
→ crazywook/probe 저장소
```

## 현재 설정

remote 확인:

```bash
git remote -v
```

예상 결과:

```text
origin  git@github.com:crazywook/probe.git (fetch)
origin  git@github.com:crazywook/probe.git (push)
```

저장소 전용 SSH 명령 확인:

```bash
git config --local --get core.sshCommand
```

예상 결과:

```text
ssh -i /Users/swkim/.ssh/id_ed25519 -o IdentitiesOnly=yes -o AddKeysToAgent=yes -o UseKeychain=yes
```

## 처음부터 설정하는 명령

### 1. 공개키를 클립보드에 복사

```bash
pbcopy < ~/.ssh/id_ed25519.pub
```

클립보드 확인:

```bash
pbpaste
```

복사한 공개키를 GitHub의 다음 위치에 등록한다.

```text
GitHub
→ Settings
→ SSH and GPG keys
→ New SSH key
```

### 2. 암호화된 개인키를 macOS Keychain과 SSH agent에 추가

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

키의 passphrase를 한 번 입력한다. 이후 macOS Keychain이 passphrase를
관리하므로 일반적인 `pull`과 `push`에서는 다시 묻지 않는다.

agent 등록 확인:

```bash
ssh-add -l
```

### 3. SSH 인증 계정 확인

```bash
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -T git@github.com
```

성공 시:

```text
Hi crazywook! You've successfully authenticated, but GitHub does not provide shell access.
```

### 4. 이 저장소의 remote를 SSH로 변경

```bash
git remote set-url origin git@github.com:crazywook/probe.git
```

### 5. 이 저장소에만 개인키 고정

```bash
git config --local core.sshCommand "ssh -i /Users/swkim/.ssh/id_ed25519 -o IdentitiesOnly=yes -o AddKeysToAgent=yes -o UseKeychain=yes"
```

이 설정은 이 저장소의 `.git/config`에만 기록된다. 다른 회사 저장소의 SSH
설정에는 영향을 주지 않는다.

### 6. HTTPS용 로컬 credential helper가 남아 있다면 제거

```bash
git config --local --unset-all credential.helper
```

설정이 없을 때 종료 코드가 0이 아닐 수 있지만 문제는 아니다.

### 7. 실제 저장소 접근 확인

```bash
git fetch origin
```

브랜치 상태 확인:

```bash
git status --short --branch
```

## 평소 인증 확인 순서

```text
git remote -v
→ SSH remote인지 확인

git config --local --get core.sshCommand
→ 이 저장소가 사용할 개인키 확인

ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -T git@github.com
→ 키가 연결된 GitHub 계정 확인

git fetch origin
→ 실제 저장소 읽기 권한 확인

git status --short --branch
→ 로컬과 원격 브랜치 상태 확인
```

복사용 명령:

```bash
git remote -v
git config --local --get core.sshCommand
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -T git@github.com
git fetch origin
git status --short --branch
```

## 이번 브랜치 정리 결과

원격과 로컬 `main`이 각각 3개 커밋씩 갈라져 있어서 rebase로 정리했다.

```bash
git pull --rebase
```

충돌을 해결한 후 다음 검증을 통과했다.

```text
TypeScript compile: 성공
테스트: 27개 통과, 0개 실패
현재 상태: main이 origin/main보다 2커밋 앞섬
```

남은 커밋을 원격에 올릴 때:

```bash
git push origin main
```

## 플로우
probe 저장소의 현재 설정을 기준으로 한 실제 흐름입니다.
1. git pull 실행

2. .git/config에서 현재 브랜치의 upstream 확인
→ main → origin/main

3. .git/config에서 remote.origin.url 확인
→ git@github.com:crazywook/probe.git

4. SSH 주소이므로 .git/config의 core.sshCommand 실행

5. 아래 명령으로 사용할 개인키를 고정
ssh -i /Users/swkim/.ssh/id_ed25519 \
  -o IdentitiesOnly=yes \
  -o AddKeysToAgent=yes \
  -o UseKeychain=yes

6. SSH가 /Users/swkim/.ssh/id_ed25519 개인키를 읽음

7. 키에 암호가 있으면 macOS Keychain에서 암호를 받아 개인키 사용

8. SSH가 개인키 소유를 증명하는 서명을 GitHub에 전송

9. GitHub가 등록된 공개키 fingerprint와 비교

10. 해당 키가 등록된 crazywook 계정으로 인증

11. crazywook 계정에 crazywook/probe 저장소 접근 권한이 있는지 확인

12. 인증 성공 후 origin/main 커밋을 다운로드

13. 전역 설정 pull.rebase = true에 따라 로컬 main 커밋을 origin/main 위로 rebase

14. 충돌이 없으면 git pull 완료

```text
git pull
→ branch.main.remote = origin
→ remote.origin.url = git@github.com:crazywook/probe.git
→ core.sshCommand
→ ~/.ssh/id_ed25519
→ macOS Keychain
→ GitHub 공개키 fingerprint
→ crazywook 계정
→ crazywook/probe 권한 확인
→ fetch
→ rebase
```
