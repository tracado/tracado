# Como o Lastro pensa

O produto é **um grafo**, não um conjunto de telas. Aqui está o que cada coisa
é, por que a norma exige, e como uma puxa a outra.

## A ideia central

Um SGSI não é uma pilha de documentos: é uma **cadeia de causa e efeito** que
precisa ficar de pé na frente de um auditor. O ativo tem valor; sobre ele pesa
um risco; o risco é tratado por um controle; o controle é comprovado por
evidência; o desvio vira não conformidade; a não conformidade tem causa raiz e
plano; o plano é verificado quanto à eficácia; e tudo alimenta a análise crítica
da direção, que decide os próximos passos.

O Lastro existe para que você **nunca digite a mesma informação duas vezes** e
para que, em qualquer ponto, seja possível responder "de onde veio isso?" e "no
que isso deu?".

## A cadeia, elo a elo

### 1. Contexto do SGSI — cláusulas 4.1, 4.2 e 6.2

Antes de proteger, é preciso saber para quem e por quê: as questões internas e
externas, as partes interessadas com o que cada uma exige, e os objetivos de
segurança com meta e prazo.

**Sai daqui:** objetivo vira risco em um clique; expectativa de parte
interessada vira risco; os objetivos alimentam as metas dos indicadores.

> **Onde se erra:** objetivo que não vira risco, meta ou ação é enfeite. A 6.2
> exige que ele seja monitorado.

### 2. Ativos de Informação — A.5.9 e ISO 27005

O que a organização protege. O Lastro separa ativo **primário** (processo,
serviço, informação — o que tem valor de negócio) de ativo de **suporte** (nuvem,
banco, pessoas, instalações — o que sustenta os primários).

**Sai daqui:** riscos sobre o ativo; atividades de tratamento de dados pessoais
(RoPA); cenários de continuidade com RTO e RPO; a saúde do ativo, que soma
riscos, NCs e planos atrasados dele.

> **Onde se erra:** inventariar só ativos de TI. Um SGSI que não enxerga
> processo e informação como ativo primário não passa na 27005 — e é o erro mais
> comum do mercado.

### 3. Análise de Riscos — 6.1.2 e 6.1.3

A ameaça (ou oportunidade) sobre o ativo, medida antes e depois do controle. O
risco **inerente** é o tamanho do problema sem tratamento; o **residual** é o que
sobra depois do controle.

> **Onde se erra:** aceitar risco sem nomear quem aprovou e quando. A 6.1.3(f)
> exige aprovação do dono do risco — o sistema recusa a aceitação sem isso.

### 4. Declaração de Aplicabilidade (SOA) — 6.1.3(d)

Os 93 controles do Anexo A com a decisão da organização sobre cada um. É o
primeiro documento que o auditor externo pede.

**Sai daqui:** a fila de GAP priorizada; o índice de Segurança Aplicada; o
roteiro da auditoria interna.

> **Onde se erra:** excluir controle sem justificar. A 6.1.3(d) exige a
> justificativa das exclusões — o sistema recusa a exclusão em branco.

### 5. Políticas e Evidências — 7.5, A.5.1 e A.5.37

Política é o que a organização **diz** que faz; evidência é o que **prova** que
faz. Política eleva o controle a "Documentado" e para por aí — só evidência
operacional sobe daí.

> **Onde se erra:** confundir os dois. Evidência vencida deixa de contar como
> cobertura, mas continua no histórico.

### 6. Eventos e Não Conformidades — A.5.24 a A.5.27, 10.1, LGPD Art. 48

Uma entrada só para tudo que acontece ou é encontrado. **Evento** é ocorrência
observada; **incidente** é o que comprometeu ou ameaça comprometer; **não
conformidade** é o desvio em relação ao que a organização se comprometeu a fazer.

Se envolve dado pessoal, dispara os prazos legais: **3 dias úteis** para a ANPD
(Resolução CD/ANPD 15/2024) e **15 dias** para o titular (Art. 19).

### 7. Causa raiz e Planos de Ação — 10.1 e 10.2

A NC exige duas coisas diferentes: a **correção imediata** (apaga o incêndio) e a
**ação corretiva** (impede o incêndio de voltar). A segunda só é possível depois
de achar a causa raiz — por 5 Porquês ou Ishikawa.

> **Onde se erra:** encerrar a NC sem verificar a eficácia. É o achado mais
> comum em recertificação. E se a mesma causa reaparecer em outra NC, o sistema
> avisa: reincidência é sinal de que a ação anterior não funcionou.

### 8. Auditoria Interna — 9.2

A organização audita a si mesma antes que alguém de fora o faça. O roteiro é
gerado do que ela declarou no SOA.

> **Onde se erra:** deixar alguém auditar o próprio trabalho. A 9.2.2(c) exige
> imparcialidade — o roteiro sinaliza quando o auditor é o dono do controle.

### 9. Análise Crítica pela Direção — 9.3

A direção olha o SGSI inteiro e decide. O sistema **congela** um retrato dos
indicadores no momento da análise — reabrir depois não recalcula, porque isso
reescreveria a história.

## O que puxa o quê

| De | Para | O que viaja junto |
|---|---|---|
| Objetivo de SI | Risco | a descrição do objetivo e o vínculo |
| Parte interessada | Risco | a expectativa declarada, no texto do risco |
| Ativo | Risco | o ativo, a criticidade e o CID afetado |
| Ativo primário | RoPA | o vínculo obrigatório — não há tratamento sem ativo |
| Cenário de continuidade | Risco | o pior impacto vira probabilidade e impacto |
| Risco | Plano de ação | o racional do impacto vira a descrição do plano |
| Risco | Não conformidade | ativo, cláusula e o relato |
| Incidente | Não conformidade | ativo, risco e a gravidade (Alta vira NC Maior) |
| Incidente com dado pessoal | Prazos legais | inicia 3 dias úteis e 15 dias |
| Achado de auditoria | Não conformidade | referência, descrição e a auditoria de origem |
| Causa raiz | Reincidência | compara com NCs anteriores e avisa se a causa voltou |
| Evidência no Anexo A | CIS e NIST | a mesma evidência conta nos controles equivalentes |
| Análise crítica | Próximo ciclo | as decisões viram a entrada 9.3.2(a) seguinte |

## Por onde começar

1. Declare o **contexto**: quem exige o quê, e quais são seus objetivos.
2. Levante os **ativos** — comece pelos primários.
3. Mapeie os **riscos** sobre eles, com o controle que os trata.
4. Preencha a **Declaração de Aplicabilidade**, justificando o que não se aplica.
5. Anexe **políticas** e **evidências** aos controles.
6. Deixe a **fila de GAP** dizer o que fazer primeiro.
7. Registre o que acontece em **Eventos & NC** e trate até a eficácia.
8. Faça a **auditoria interna** e leve o resultado à **análise crítica**.

Não precisa ser linear: o **Saneador Inteligente** deixa entrar por qualquer
ponto, e o sistema completa a cadeia a partir de onde você está.
