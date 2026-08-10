# 출력 방식
내용이 길다면 요약을 항상 먼저 보여주고 뒤에서 설명한다.

# Github
PR작성시 나 자신으로 assign

# 코드 컨벤션

- **Clean Code** 원칙을 따른다.
- **`if`/`else`/`for`/`while` 등 모든 제어문은 본문이 한 줄이어도 반드시 중괄호 `{}`로 감싼다.** 중괄호 없는 단문(`if (x) doSomething()`)을 쓰지 않는다.

# 작업 방식

- **파일 편집 후 `prettier`(예: `npx prettier --write`)를 수동으로 매번 실행하지 않는다.** 에디터의 저장 시 자동 포맷(format on save)이 처리한다.

# sh 명령 양식 제한
모든 옵션은 최대한 뒤로 뺀다.
예:
  kubectl get ns argocd --context
