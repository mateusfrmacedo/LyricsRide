# Lyrics Ride

Protótipo iOS de letras sincronizadas na Lock Screen, Dynamic Island e CarPlay via Live Activities.

## Rodar no iPhone

1. Abra `LyricsRide.xcodeproj` no Xcode 16+.
2. Em **Signing & Capabilities**, escolha o seu `Personal Team`. Isso basta para teste local; a instalação expira em 7 dias.
3. Conecte um iPhone físico com iOS 16.1+ (um iPhone com Dynamic Island é necessário para testar essa apresentação).
4. Escolha o iPhone como destino e rode (`⌘R`). Toque em **Mostrar letras dinâmicas** e bloqueie o aparelho.

## Configurar Spotify

1. No [Spotify Developer Dashboard](https://developer.spotify.com/dashboard), crie um app do tipo **iOS**.
2. Use o Bundle ID `com.mateus.lyricsride` e cadastre exatamente o Redirect URI `lyricsride://spotify-callback`.
3. O Client ID do app Spotify já foi configurado. Nunca acrescente Client Secret ao app.
4. Instale e entre no Spotify no iPhone. Em Development Mode, adicione cada conta de teste à allowlist do app no Dashboard.

O app usa o Spotify iOS SDK para a faixa/posição e LRCLIB apenas como fonte de letras LRC. A sincronização continua enquanto o app está ativo; iOS pode suspender atualizações quando o app está em segundo plano. A interface inclui a ação de atualização manual justamente para o caso de a letra ficar defasada.

## TestFlight

Para enviar a terceiros pelo TestFlight, assine o Apple Developer Program. Para teste pessoal por Xcode, não é necessário.
