# Roteiro do vídeo (2–3 minutos)

Objetivo: mostrar que o sistema de roda, loadout e habilidades funciona, e que o código é organizado. Não precisa de narração perfeita; o que importa é mostrar cada coisa funcionando.

## Antes de gravar

- Parar o Studio, reconectar o Rojo (porta 34873) e dar **Play** com a versão atual.
- Ter pelo menos um bot de treino à frente (eles aparecem a uns 22 studs do spawn).
- Fechar qualquer janela ou aba que apareça no vídeo.

## Cenas

| Tempo | O que mostrar | O que dizer (curto) |
|---|---|---|
| 0:00–0:15 | Tela inicial do jogo, com o indicador "[Q] Abilities  [R] Spells" acima do HUD. | "Um protótipo de roda de habilidades para um jogo sobrenatural, feito em Luau com Rojo." |
| 0:15–0:35 | Segurar **Q**: a roda Q abre. Passar o cursor numa habilidade equipada e soltar Q. A habilidade fica selecionada no HUD. | "Segurar Q abre a roda. Soltar seleciona a habilidade em foco, sem ativar nada." |
| 0:35–0:50 | Clicar em **USE** (ou clicar no mundo) e mostrar o dash. Mostrar a recarga no HUD. | "A habilidade é validada no servidor: o cooldown e o estado do personagem são conferidos antes de qualquer efeito." |
| 0:50–1:15 | Abrir **SPELLS**. Mostrar a grade agrupada por categoria, clicar numa habilidade equipada e mostrar que ela sai do slot. Clicar de novo e mostrar que ela volta no primeiro slot vazio. | "Equipar e remover são pedidos ao servidor. A habilidade sai do slot, mas continua disponível no painel." |
| 1:15–1:35 | Ainda na edição, tentar equipar a mesma habilidade na roda R. Mostrar a mensagem "already in the other wheel". | "Uma habilidade só pode estar em uma roda. O servidor recusa a duplicata." |
| 1:35–1:55 | Apertar **R** e mostrar a roda R; apertar **Q** para voltar; clicar no centro para alternar. | "Q e R trocam de roda. Clicar no centro também." |
| 1:55–2:20 | Usar o Estrangulamento Telecinético num bot: mostrar o alvo sendo erguido, a barra de vida caindo e o efeito terminando. | "A habilidade do choque valida distância, frente e linha de visão no servidor, aplica o dano em pulsos e restaura o personagem no fim." |
| 2:20–2:45 | Abrir o repositório no editor: `Config.lua`, `AbilityService.lua` e `LoadoutService.lua`. | "Cada habilidade é uma entrada no Config e um módulo no servidor. Adicionar uma é repetir esse padrão. O README mostra os passos." |
| 2:45–3:00 | Voltar à roda e fechar com **CLOSE**. | "Próximos passos: seleção de personagem, mais espécies e mais rodas." |

## Depois de gravar

- Conferir no vídeo se os textos da roda estão legíveis.
- Se alguma cena não funcionar, cortar em vez de explicar o erro. Se for importante, explicar em uma frase no README.
- Não mostrar a aba de saída com erros. Se houver avisos do DataStore (eles aparecem sem a publicação do lugar), ignorar a cena ou mostrar a explicação do README.
