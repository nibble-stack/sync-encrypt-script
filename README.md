# Encrypted multi-provider sync setup

This repo contains scripts and example configuration to manage encrypted (`crypt`) and plain (`sync`) datasets across multiple cloud providers (Google Drive, Dropbox, Proton, etc.), with automatic 5-version backup rotation both locally and in the cloud.

## Folder structure

```text
~/Sync/
  <prov>/
    <prov>-crypt/
      <prov>-crypt-01/
      <prov>-crypt-02/
    <prov>-decrypt/
      <prov>-decrypt-01/
      <prov>-decrypt-02/
    <prov>-sync/
      <prov>-sync-01/
      <prov>-sync-02/

~/Sync-backups/
  <prov>/
    <prov>-crypt-bak/
      <prov>-crypt-bak-01/
        <timestamps...>
    <prov>-sync-bak/
      <prov>-sync-bak-01/
        <timestamps...>

