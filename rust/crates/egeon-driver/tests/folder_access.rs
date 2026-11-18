//! O executável de teste não está num `.app`: a decisão do usuário não existe e
//! não há o que zerar. O `tccutil` de verdade nunca roda aqui.

use egeon_core::ports::folder_access::FolderPermissions;
use egeon_driver::SystemFolderPermissions;

#[test]
fn fora_de_um_app_nao_ha_o_que_zerar() {
    assert!(!SystemFolderPermissions.reset("SystemPolicyDocumentsFolder"));
    assert!(!SystemFolderPermissions.reset("SystemPolicyDesktopFolder"));
}
