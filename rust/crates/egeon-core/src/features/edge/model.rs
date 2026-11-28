//! A aresta (quem pode acionar quem) e a ligação (o par visto como uma coisa
//! só). Porte do `EdgeConfig` e do `EdgeLink`.

use serde::{Deserialize, Deserializer, Serialize};

/// Duas idas e voltas: delega, recebe, ajusta, recebe. É o ciclo útil mais
/// comum, e o próximo já costuma ser repetição.
///
/// Baixo de propósito. Turno de agente degrada com a quantidade de rodadas
/// mesmo sobrando contexto, e isto roda enquanto você está longe da máquina:
/// errar para menos custa uma rodada a mais pedida por você; errar para mais
/// custa tempo e token sem ninguém olhando.
pub const DEFAULT_SENDS: i64 = 2;

/// Uma ligação dirigida entre dois nós da mesma bancada: `from` pode acionar
/// `to`.
///
/// Sempre de mão única, e ida e volta continuam sendo DUAS: é o que faz o ciclo
/// de dois e o de três serem o mesmo mecanismo, com `maxSends` e autorização
/// raciocinando por sentido (ADR-012). O par é desenhado como uma linha só (ADR-028).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EdgeConfig {
    pub from: String,
    pub to: String,
    /// Quantas vezes esta seta pode disparar na mesma conversa. `None` = sem
    /// limite próprio, vale só o teto da bancada. Só aperta, nunca afrouxa.
    ///
    /// Chave ausente e `null` explícito são coisas diferentes na LEITURA:
    /// ausente herda o padrão, `null` desliga o limite desta seta.
    ///
    /// Defeito do Swift portado como está: o `null` não volta ao disco (o
    /// encoder omite o opcional nulo), então na próxima leitura vira o padrão.
    #[serde(
        default = "default_sends",
        rename = "maxSends",
        deserialize_with = "present_or_null",
        skip_serializing_if = "Option::is_none"
    )]
    pub max_sends: Option<i64>,
}

fn default_sends() -> Option<i64> {
    Some(DEFAULT_SENDS)
}

/// Só roda com a chave presente: `null` é `None`, número é `Some`.
fn present_or_null<'de, D: Deserializer<'de>>(de: D) -> Result<Option<i64>, D::Error> {
    Option::<i64>::deserialize(de)
}

impl EdgeConfig {
    pub fn new(from: impl Into<String>, to: impl Into<String>, max_sends: Option<i64>) -> Self {
        Self {
            from: from.into(),
            to: to.into(),
            max_sends,
        }
    }

    /// Uma aresta nova, com o limite padrão.
    pub fn with_default_limit(from: impl Into<String>, to: impl Into<String>) -> Self {
        Self::new(from, to, default_sends())
    }
}

/// Igualdade só por origem e destino: é o que identifica a ligação. Duas
/// arestas entre o mesmo par não existem, e comparar o limite junto faria
/// `contains` falhar depois de você editar o número.
impl PartialEq for EdgeConfig {
    fn eq(&self, other: &Self) -> bool {
        self.from == other.from && self.to == other.to
    }
}

impl Eq for EdgeConfig {}

/// As arestas entre dois nós, colapsadas no que a tela mostra: uma linha com
/// ponta em cada extremidade que tem sentido — `───▶`, `◀───` ou `◀───▶`.
///
/// Guarda o par em ordem de nome para ter identidade estável; quem é a origem
/// do TRAÇADO é decidido na hora de desenhar, pela posição dos cards.
#[derive(Debug, Clone)]
pub struct EdgeLink {
    pub a: String,
    pub b: String,
    /// `a` pode acionar `b`. Na tela, ponta do lado de `b`.
    pub a_to_b: bool,
    /// `b` pode acionar `a`. Na tela, ponta do lado de `a`.
    pub b_to_a: bool,
    /// Limite da ligação. Com os dois sentidos divergindo no arquivo editado à
    /// mão, vale o de `a→b` — a pastilha grava nos dois.
    pub max_sends: Option<i64>,
}

impl EdgeLink {
    pub fn is_bidirectional(&self) -> bool {
        self.a_to_b && self.b_to_a
    }

    /// As arestas reais, que são o que vive no `workbenches.json` e o que as
    /// guardas leem.
    pub fn edges(&self) -> Vec<EdgeConfig> {
        let mut out = Vec::new();
        if self.a_to_b {
            out.push(EdgeConfig::new(&self.a, &self.b, self.max_sends));
        }
        if self.b_to_a {
            out.push(EdgeConfig::new(&self.b, &self.a, self.max_sends));
        }
        out
    }

    /// Próximo estado do botão: ida → ida e volta → volta → ida.
    ///
    /// Nunca passa por "nenhum dos dois": ligação sem sentido nenhum não é uma
    /// linha, é uma linha removida, e para isso existe o X ao lado.
    pub fn cycled(&self) -> EdgeLink {
        let mut next = self.clone();
        match (self.a_to_b, self.b_to_a) {
            (true, false) => {
                next.a_to_b = true;
                next.b_to_a = true;
            }
            (true, true) => {
                next.a_to_b = false;
                next.b_to_a = true;
            }
            _ => {
                next.a_to_b = true;
                next.b_to_a = false;
            }
        }
        next
    }

    /// O par em ordem de nome.
    pub fn pair<'a>(x: &'a str, y: &'a str) -> (&'a str, &'a str) {
        if x <= y { (x, y) } else { (y, x) }
    }

    /// Colapsa as arestas de uma bancada em ligações, na ordem em que aparecem.
    pub fn collapse(edges: &[EdgeConfig]) -> Vec<EdgeLink> {
        let mut links: Vec<EdgeLink> = Vec::new();
        for edge in edges {
            let (a, b) = Self::pair(&edge.from, &edge.to);
            let forward = edge.from == a;
            match links.iter_mut().find(|l| l.a == a && l.b == b) {
                Some(link) if forward => {
                    link.a_to_b = true;
                    // O limite do sentido a→b manda quando existe: sem esta
                    // regra, qual dos dois números aparece dependeria da ordem
                    // do arquivo.
                    link.max_sends = edge.max_sends;
                }
                Some(link) => {
                    link.b_to_a = true;
                    if !link.a_to_b {
                        link.max_sends = edge.max_sends;
                    }
                }
                None => links.push(EdgeLink {
                    a: a.to_owned(),
                    b: b.to_owned(),
                    a_to_b: forward,
                    b_to_a: !forward,
                    max_sends: edge.max_sends,
                }),
            }
        }
        links
    }
}

/// Igualdade só pelo par: é o que identifica a linha na tela. Trocar a direção
/// não faz dela outra ligação — o realce sob o cursor precisa sobreviver ao
/// clique no botão.
impl PartialEq for EdgeLink {
    fn eq(&self, other: &Self) -> bool {
        self.a == other.a && self.b == other.b
    }
}

impl Eq for EdgeLink {}

#[cfg(test)]
mod tests {
    use super::*;

    fn link(a_to_b: bool, b_to_a: bool, max_sends: Option<i64>) -> EdgeLink {
        EdgeLink {
            a: "a".into(),
            b: "b".into(),
            a_to_b,
            b_to_a,
            max_sends,
        }
    }

    fn edge(from: &str, to: &str, max: Option<i64>) -> EdgeConfig {
        EdgeConfig::new(from, to, max)
    }

    // O par é guardado em ordem de nome para ter identidade estável.
    #[test]
    fn par_ordena_por_nome() {
        assert_eq!(EdgeLink::pair("zeta", "alfa"), ("alfa", "zeta"));
        assert_eq!(EdgeLink::pair("alfa", "zeta"), ("alfa", "zeta"));
    }

    #[test]
    fn colapsar_junta_os_dois_sentidos_numa_ligacao() {
        let links = EdgeLink::collapse(&[edge("b", "a", Some(2)), edge("a", "b", Some(2))]);
        assert_eq!(links.len(), 1);
        assert!(links[0].is_bidirectional());
        assert_eq!((links[0].a.as_str(), links[0].b.as_str()), ("a", "b"));
    }

    // Com os sentidos divergindo no arquivo editado à mão, vale o limite de a→b
    // — independente da ordem em que as arestas aparecem.
    #[test]
    fn colapsar_vale_o_limite_de_a_para_b() {
        let links = EdgeLink::collapse(&[edge("b", "a", Some(9)), edge("a", "b", Some(3))]);
        assert_eq!(links[0].max_sends, Some(3));
        let links = EdgeLink::collapse(&[edge("a", "b", Some(3)), edge("b", "a", Some(9))]);
        assert_eq!(links[0].max_sends, Some(3));
    }

    #[test]
    fn colapsar_mantem_a_ordem_de_aparicao() {
        let links = EdgeLink::collapse(&[edge("c", "d", None), edge("a", "b", None)]);
        assert_eq!(
            links.iter().map(|l| l.a.as_str()).collect::<Vec<_>>(),
            ["c", "a"]
        );
    }

    // O botão da linha: ida → ida e volta → volta → ida. Nunca passa por
    // "nenhum sentido" — para isso existe o X.
    #[test]
    fn ciclo_nunca_chega_a_nenhum_sentido() {
        let ida = link(true, false, None);
        let ida_e_volta = ida.cycled();
        assert!(ida_e_volta.a_to_b && ida_e_volta.b_to_a);
        let volta = ida_e_volta.cycled();
        assert!(!volta.a_to_b && volta.b_to_a);
        let de_novo_ida = volta.cycled();
        assert!(de_novo_ida.a_to_b && !de_novo_ida.b_to_a);
    }

    #[test]
    fn so_os_sentidos_ativos_viram_arestas() {
        let edges = link(false, true, Some(5)).edges();
        assert_eq!(edges, [edge("b", "a", None)]);
        assert_eq!(edges[0].max_sends, Some(5));
    }

    // Igualdade só pelo par: trocar a direção é a MESMA linha mudando de estado.
    #[test]
    fn igualdade_da_ligacao_ignora_a_direcao() {
        assert_eq!(link(true, false, None), link(false, true, Some(7)));
    }

    // A igualdade ignora o limite: `contains` continua achando a aresta depois
    // de você editar o número.
    #[test]
    fn igualdade_da_aresta_ignora_o_limite() {
        assert_eq!(edge("a", "b", Some(1)), edge("a", "b", Some(99)));
        assert_ne!(edge("a", "b", None), edge("b", "a", None));
    }

    // Chave ausente herda o padrão (2); null explícito desliga o limite da seta.
    #[test]
    fn leitura_distingue_ausente_de_null() {
        let absent: EdgeConfig = serde_json::from_str(r#"{"from":"a","to":"b"}"#).unwrap();
        assert_eq!(absent.max_sends, Some(DEFAULT_SENDS));
        let null: EdgeConfig =
            serde_json::from_str(r#"{"from":"a","to":"b","maxSends":null}"#).unwrap();
        assert_eq!(null.max_sends, None);
        let set: EdgeConfig =
            serde_json::from_str(r#"{"from":"a","to":"b","maxSends":5}"#).unwrap();
        assert_eq!(set.max_sends, Some(5));
        assert!(serde_json::from_str::<EdgeConfig>(r#"{"from":"a"}"#).is_err());
        assert!(
            serde_json::from_str::<EdgeConfig>(r#"{"from":"a","to":"b","maxSends":"x"}"#).is_err()
        );
    }

    // Defeito do Swift, portado: o null explícito não é gravado, e ao reler vira 2.
    #[test]
    fn null_nao_volta_ao_disco_e_reabre_como_o_padrao() {
        let null = edge("a", "b", None);
        let text = serde_json::to_string(&null).unwrap();
        assert_eq!(text, r#"{"from":"a","to":"b"}"#);
        let back: EdgeConfig = serde_json::from_str(&text).unwrap();
        assert_eq!(back.max_sends, Some(DEFAULT_SENDS));
    }
}
