//! Interface de tela: o emulador por trás de cada nó de terminal.
//!
//! Implementada por `egeon-terminal`, sobre o libghostty-vt. Os bytes do pty
//! entram; saem os quadros que a UI pinta, o texto que o `peek` lê, o tamanho,
//! os bytes de uma tecla e o que o terminal responde ao programa. Os quadros já
//! vêm nos tipos do fio ([`crate::protocol::screen`]), para o runtime só
//! embrulhá-los no evento.
//!
//! Tudo aqui volta na hora e sem E/S: a tela vive dentro do ator, que a chama
//! entre uma mensagem e outra. Ler a tela também pede `&mut`, porque o
//! emulador atualiza o estado de renderização a cada leitura.

use thiserror::Error;

use crate::protocol::screen::{Effect, Frame, KeyPress, Pointer, Scroll, Size};

/// A tela de um terminal.
pub trait Screen: Send {
    /// Processa a saída do programa.
    fn feed(&mut self, bytes: &[u8]);

    /// O que o terminal respondeu ao programa desde a última chamada (posição
    /// do cursor, atributos do dispositivo, consulta de modo). Tem de voltar
    /// para o pty: um programa que pergunta e não ouve resposta fica esperando.
    fn take_responses(&mut self) -> Vec<u8>;

    /// Muda colunas × linhas. A tela refaz a quebra das linhas longas, e o
    /// próximo [`Screen::take_delta`] vem inteiro.
    fn resize(&mut self, size: Size) -> Result<(), ScreenError>;

    fn size(&self) -> Size;

    /// Todas as linhas, com `kind` `Full`. Não dá nada por entregue: quem
    /// acabou de assinar não tira dos outros as mudanças pendentes.
    fn full_frame(&mut self) -> Frame;

    /// As linhas alteradas desde a última chamada, que passam a contar como
    /// entregues. `None` quando nada mudou. Cursor que só andou também gera
    /// quadro; nele podem vir a linha de onde ele saiu e a para onde foi, mesmo
    /// sem texto novo. Se a tela inteira mudou (limpeza, tela alternativa,
    /// resize), vem com `kind` `Full` e todas as linhas.
    fn take_delta(&mut self) -> Option<Frame>;

    /// Cada linha visível, de cima para baixo, como texto: célula em branco é
    /// espaço, e nada é cortado — o corte e o filtro do `peek` são do core.
    ///
    /// São as linhas da vista: rolada para o histórico, é o histórico que sai,
    /// como no `getLine(row:)` do SwiftTerm que o `peek` de hoje usa.
    fn rows_text(&mut self) -> Vec<String>;

    /// Os bytes que a tecla manda ao programa, no modo em que a tela está agora
    /// (cursor de aplicação, protocolo de teclado do kitty…). Vazio quando a
    /// tecla não produz nada.
    fn encode_key(&mut self, key: &KeyPress) -> Vec<u8>;

    /// Se o programa ligou o bracketed paste (DECSET 2004, `ESC[?2004h`) e
    /// ainda não desligou: aí a colagem vai embrulhada em `ESC[200~…ESC[201~`.
    /// Vale o modo de agora — o zsh, por exemplo, só o liga enquanto edita a
    /// linha.
    fn bracketed_paste(&self) -> bool;

    /// Leva a vista pelo histórico. Saída nova só puxa a vista para o fim se
    /// ela já estava lá; quem escreve entrada do usuário no pty pede `Bottom`
    /// antes, como o SwiftTerm faz a cada envio.
    fn scroll(&mut self, to: Scroll);

    /// Um gesto do ponteiro. Com o mouse ligado pelo programa (e sem shift),
    /// devolve os bytes do relatório para o pty; senão o gesto vira seleção, a
    /// roda rola a vista — ou, na tela alternativa, vira setas, que também
    /// voltam aqui para o pty. Vazio quando não há nada a mandar.
    fn pointer(&mut self, event: &Pointer) -> Vec<u8>;

    fn select_all(&mut self);

    /// O texto selecionado, com as linhas que o terminal quebrou juntadas de
    /// volta e os espaços do fim cortados. `None` sem seleção.
    fn selection_text(&mut self) -> Option<String>;

    /// A resposta, para o pty, à consulta da área de transferência mais antiga
    /// ainda sem resposta ([`Effect::ClipboardRequest`]), com `text` dentro.
    /// Vazio se não há consulta pendente.
    fn clipboard_answer(&mut self, text: &str) -> Vec<u8>;

    /// Sino, gravações e consultas da área de transferência desde a última
    /// chamada.
    fn take_effects(&mut self) -> Vec<Effect>;

    /// O que está sob a célula da vista, para o ⌘-clique: o hiperlink
    /// explícito (OSC 8), senão a URL ou o caminho que a regex do Ghostty acha
    /// (com a linha quebrada juntada), senão o nome solto com `.` ou `/`
    /// (`README.md`). Cru: resolver contra as pastas é do core.
    fn link_at(&mut self, col: u16, row: u16) -> Option<LinkHit>;
}

/// O que o ⌘-clique achou, e de onde: o Swift trata os dois de jeito
/// diferente.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LinkHit {
    /// Hiperlink explícito ou o que a regex achou: o clique é dele — o
    /// programa não recebe o soltar, e sem destino o app apita.
    Link(String),
    /// Nome solto: o soltar vai ao programa antes, e o arquivo só abre se
    /// existir, sem apito quando não existe (`MBTerminalView.mouseUp`).
    Word(String),
}

/// Cria telas. O core recebe uma, na partida, e cria uma tela por nó.
pub trait ScreenFactory: Send + Sync {
    fn create(&self, size: Size) -> Result<Box<dyn Screen>, ScreenError>;
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ScreenError {
    #[error("tamanho de tela inválido: {cols}×{rows}")]
    InvalidSize { cols: u16, rows: u16 },
    #[error("o emulador recusou: {0}")]
    Engine(String),
}
