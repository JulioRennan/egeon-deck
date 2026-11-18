//! De onde os varredores do catálogo leem o binário do Claude Code.
//!
//! O executável passa de 300 MB. O Swift o mapeia (`.alwaysMapped`) e o SO só
//! traz as páginas tocadas; o core não tem `unsafe`, então a leitura é em blocos:
//! um buffer de [`BLOCK`] bytes que anda pelo arquivo, memória constante, com o
//! mesmo resultado de varrer o arquivo inteiro na memória.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

/// Quanto do binário fica na memória de cada vez.
pub const BLOCK: usize = 1024 * 1024;

/// Os bytes de um binário, por posição absoluta.
pub trait Bytes {
    fn size(&self) -> usize;

    /// A primeira ocorrência de `needle` em `[from..]`, como posição absoluta.
    fn find(&mut self, needle: &[u8], from: usize) -> Option<usize>;

    /// `[start..end]`, com o fim cortado no tamanho do binário.
    fn slice(&mut self, start: usize, end: usize) -> Vec<u8>;
}

impl Bytes for &[u8] {
    fn size(&self) -> usize {
        <[u8]>::len(self)
    }

    fn find(&mut self, needle: &[u8], from: usize) -> Option<usize> {
        if from >= <[u8]>::len(self) || needle.is_empty() {
            return None;
        }
        memchr::memmem::find(&self[from..], needle).map(|at| from + at)
    }

    fn slice(&mut self, start: usize, end: usize) -> Vec<u8> {
        let end = end.min(<[u8]>::len(self));
        self[start.min(end)..end].to_vec()
    }
}

/// O binário em disco, lido por blocos. Erro de leitura no meio (o binário foi
/// trocado durante a varredura) vira fim dos dados e acende [`failed`]: quem
/// chamou descarta o resultado em vez de gravar um catálogo pela metade.
///
/// [`failed`]: FileBytes::failed
pub struct FileBytes {
    file: File,
    len: usize,
    block: usize,
    base: usize,
    buf: Vec<u8>,
    failed: bool,
}

impl FileBytes {
    pub fn open(path: &Path) -> Option<FileBytes> {
        FileBytes::open_with_block(path, BLOCK)
    }

    /// Bloco menor que o de produção, para o teste cruzar fronteiras sem um
    /// arquivo de centenas de MB.
    pub fn open_with_block(path: &Path, block: usize) -> Option<FileBytes> {
        let file = File::open(path).ok()?;
        let len = usize::try_from(file.metadata().ok()?.len()).ok()?;
        Some(FileBytes {
            file,
            len,
            block: block.max(1),
            base: 0,
            buf: Vec::new(),
            failed: false,
        })
    }

    pub fn failed(&self) -> bool {
        self.failed
    }

    #[cfg(test)]
    pub fn capacity(&self) -> usize {
        self.buf.capacity()
    }

    /// Traz para o buffer o bloco que começa em `at` — e o que mais for preciso
    /// para caber `want` bytes de uma vez.
    fn load(&mut self, at: usize, want: usize) {
        let size = self.block.max(want).min(self.len.saturating_sub(at));
        self.buf.clear();
        self.buf.reserve_exact(size);
        self.buf.resize(size, 0);
        self.base = at;
        let read = self
            .file
            .seek(SeekFrom::Start(at as u64))
            .and_then(|_| self.file.read_exact(&mut self.buf));
        if read.is_err() {
            self.failed = true;
            self.buf.clear();
        }
    }

    fn end(&self) -> usize {
        self.base + self.buf.len()
    }
}

impl Bytes for FileBytes {
    fn size(&self) -> usize {
        self.len
    }

    fn find(&mut self, needle: &[u8], from: usize) -> Option<usize> {
        let mut from = from;
        let mut reload = false;
        loop {
            if self.failed || from >= self.len || needle.is_empty() {
                return None;
            }
            if reload || from < self.base || from >= self.end() {
                self.load(from, needle.len());
                if self.failed {
                    return None;
                }
            }
            let rel = from - self.base;
            if let Some(at) = memchr::memmem::find(&self.buf[rel..], needle) {
                return Some(self.base + rel + at);
            }
            let end = self.end();
            if end >= self.len {
                return None;
            }
            // O padrão pode atravessar o fim do bloco: o próximo começa
            // `needle.len() - 1` antes dele.
            from = from.max(end.saturating_sub(needle.len() - 1));
            reload = true;
        }
    }

    fn slice(&mut self, start: usize, end: usize) -> Vec<u8> {
        let end = end.min(self.len);
        if self.failed || start >= end {
            return Vec::new();
        }
        if start < self.base || end > self.end() {
            self.load(start, end - start);
            if self.failed {
                return Vec::new();
            }
        }
        self.buf[start - self.base..end - self.base].to_vec()
    }
}
