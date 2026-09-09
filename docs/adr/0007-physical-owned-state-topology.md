# ADR 0007: Physical Owned-State Topology

## Status

Accepted

## Context

SchneeGlassはConfigurationとPending Copy metadataをApplication Support配下へ保存します。

従来の実装には次のpath-following APIが残っていました。

```text
Data(contentsOf:)
Data.write(..., .atomic)
FileManager.createDirectory(..., withIntermediateDirectories: true)
FileManager.contentsOfDirectory(...)
```

leaf fileだけでなく`Configuration` / `Backups` / `Preserved` / `FileOperations` directory自体がsymbolic linkへ置換された場合、SchneeGlass-owned stateのread/writeがリンク先へ到達する余地があります。

Backup entry単体については`O_NOFOLLOW` readを導入済みでしたが、directory topologyとcurrent metadata fileには同じ保証がありませんでした。

## Decision

Darwin / Foundationだけに依存するinternal infrastructure targetとして`SchneeGlassPOSIXSupport`を追加します。

```text
SchneeGlassPOSIXSupport
  ├ Foundation
  └ Darwin

SchneeGlassFileSystemAdapter
  └ SchneeGlassPOSIXSupport

SchneeGlassPersistenceAdapter
  └ SchneeGlassPOSIXSupport
```

Domain / Application / Presentation / MacOSAdapterはこのtargetへ依存しません。

`PhysicalStateStore`をSchneeGlass-owned metadataのfilesystem authorityとします。

### Directory contract

App-owned rootとそのdescendant directoryは、directory FDから次の形で開きます。

```text
openat(parentFD, component, O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
```

存在しないowned directoryの作成は`mkdirat`を使用し、作成後に同じno-follow条件で再openします。

symbolic link、regular file、その他のnon-directory entryはfail-closedです。

### File read contract

State leafは次を満たす場合だけreadします。

```text
openat(..., O_RDONLY | O_NOFOLLOW)
→ fstat
→ physical regular file
→ read from pinned FD
```

pathを検査した後に`Data(contentsOf:)`で再openしません。

### Atomic write contract

State writeは同じphysical directory内にexclusive temporary regular fileを作成し、dataを書き込み、`fsync`後に`renameat`でcommitします。

```text
openat(O_CREAT | O_EXCL | O_NOFOLLOW)
→ write
→ fsync(temp FD)
→ existing entry identity再確認
→ renameat(temp, final)
```

`renameat`成功をvisible stateのfinal fallible commit stepとし、その後のhousekeeping failureを新しいsave failureとして報告しません。

既存final entryがsymlink / directory / non-regular fileの場合はcommitしません。

### Listing / removal contract

Owned directory listingはdirectory FDから`readdir`し、各entryを`fstatat(..., AT_SYMLINK_NOFOLLOW)`で分類します。

regular fileとして確認できたentryだけがrotation対象になります。

Removalはphysical regular-file identityを再確認してから`unlinkat`し、symbolic link targetをfollowしません。

## Configuration behavior

`JSONConfigurationStore`は次を`PhysicalStateStore`へ移行します。

```text
Configuration/config.json
Configuration/Backups/*
Configuration/Preserved/*
```

Configuration-owned directory topologyがunsafeな場合は`ConfigurationPersistenceError.unsafeStorageTopology`でfail-closedします。

個別backup entryがsymlink / non-regularの場合はRecovery候補として公開しません。

## Pending Copy behavior

Production compositionではApplication Support bundle directoryをphysical rootとし、その下の`FileOperations`をno-followでopenします。

```text
<Application Support>/io.github.lamy210.schneeglass
  └ FileOperations
      └ pending-copies.json
```

`pending-copies.json`または`FileOperations`がunsafe topologyならmetadata read/writeを拒否します。

## Consequences

### Positive

- owned metadata symlink traversalをread/write両方で閉じる
- directory replacementとleaf replacementを同じprimitiveで扱える
- PersistenceAdapterとFileSystemAdapterでPOSIX safety implementationが分岐しない
- Domain/ApplicationへFDやDarwin APIを漏らさない
- atomic configuration semanticsを維持できる

### Cost

- SPM targetが1つ増える
- Foundation-only persistenceよりPOSIX implementationのtest responsibilityが増える
- macOS固有filesystem semanticsをCIで継続検証する必要がある

## Enforcement

Architecture Guardは`SchneeGlassPOSIXSupport`からDomain/Application/Presentation/Concrete Adapter importを禁止します。

File Safety Guardは`mkdirat` / `renameat` / `unlinkat` / state-file `O_CREAT`を`PhysicalStateStore.swift`だけにallowlistします。

実Filesystem testsでroot symlink、descendant directory symlink、leaf symlink、regular-file round trip、listing/removalを検証します。
