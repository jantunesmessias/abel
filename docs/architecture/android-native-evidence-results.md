# Resultado executado do Android Evidence

Data: 2026-08-09. Baseline: Flutter 3.44.8, Dart 3.12.2, Linux x86_64,
Android Emulator API 35/x86_64.

## Entregue

- provider Android no mesmo `Evidence`/`ExecutionFingerprint` das fases
  anteriores;
- screenshot PNG, snapshot semântico sanitizado, logcat sanitizado, screen
  recording MP4 e trace Perfetto;
- manifest correlacionado de ambiente, toolchain, containment e estado por
  modalidade;
- políticas de mídia sintética e degradação independente;
- comparação visual por RGBA e semântica por JCS, ambas versionadas;
- CLI de coleta, export de artifact e comparação;
- persistência no CAS/frescor/release do workspace consumidor;
- runner ADB com output limitado, timeout TERM→KILL e boot readiness completa.

## Gate host-native observado

O modo Android Evidence de `tools/verify/verify_android_evidence.sh` terminou com exit `0` no run
`run-140964`. O fluxo criou AVD efêmero, compilou/instalou APK debug, verificou
Gateway por `adb reverse`, retomada exata da activity e coletou:

| Role | Digest | Bytes |
|------|--------|------:|
| `android.environment` | `sha256:ba12bf9ac804fb827ac926abeab8e9662a8056e0e8eb7f76b917870e451c3a6c` | 1.713 |
| `android.screenshot` | `sha256:9d79a6ab497b9915544faeadfdd865c18412c203ca0073a24cb9384fd3cacc85` | 77.000 |
| `android.performance-trace` | `sha256:cf5f24257be1934af251275ed3a8d6e5b8be6c0d34398e83967ff944627b8726` | 443.000 |
| `android.logcat` | `sha256:9d17eb1f5b5720f8bec1d160d452f2491de1c5b53795bf2d9e4f4ebdc4b437a7` | 10.638 |
| `android.screen-recording` | `sha256:61b2914d2eb9fa3a6839e4a77d6eb6c444c1a1fe81bb07b8161a31c9f65fe96d` | 34.235 |
| `android.semantics` | `sha256:c230a376652ea2863174ce10b3528f3466765a69d3076719382c5dd29a465844` | 4.303 |

O PNG observado foi 1080×2400. O fingerprint foi
`sha256:4d5bf3943c8376bfe56fb24c5836afdbe18e91f36fb84f86cc982db99dc631ae`;
o Evidence foi
`sha256:f19274afd413b0b2c7c2cb101dcae66995587d014747d94126128aa74a91fe7c`.
As cinco observações ficaram `collected`.

O compare visual exato avaliou 2.592.000 pixels e o semântico 14 nodes, ambos
com zero mudança. A release
`sha256:ff92c7b05ae93329294c336a382f129aaae01df20652313be21188ee942a1bab`
gerou bundle semântico
`sha256:14d429f5cc70aca9873a5182574111bd4a67bbe7f903f7ba961914da842f7624`.
O `.evidence.zip` de 584.667 bytes foi verificado offline com archive digest
`sha256:c845533fc8eb2b86fa76e0b6951790b1c4566bc0bfe166d77838c9738fb60ad6`
e manifest digest
`sha256:79842d660c900cda2ab583390d2c45a7522fee63b57a627e627a826157a1c8a9`.

Após a prova, package data, CA, `adb reverse`, ownership state, AVD, listeners e
processos foram removidos. O emulador previamente anexado `emulator-5554` não
foi alterado.

## Privacidade e limites honestos

Semântica e logcat exportados foram validados como `hashedTextweb/Android` e
`hashedMessageweb/Android`, sem campos crus. Mídia foi autorizada porque o sample usa
dados sintéticos. A contenção Android observada é `gatewayOnly`, não
`targetEnforced`; o emulador é `hostNative`, nunca `deviceAttested`.

Android Evidence não afirma iOS, dispositivo físico, hosted collaboration, remote runtime ou
device farm. Esses itens permanecem hosted control plane/remote execution ou posteriores.
