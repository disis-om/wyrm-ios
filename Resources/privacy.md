# Wyrm — Privacy

Last updated 25 September 2026. Wyrm is made by OM Rajput. This is the iPhone
edition of the same document the Android app carries; the parts that differ are
the ones about how you sign in and where secrets are kept.

This is written to be read, not to be scrolled past. If something here is
unclear, that is a fault worth reporting.

---

## The short version

- On iPhone you sign in with a **username and a password** you choose. Wyrm does
  not ask Apple, Google or anyone else who you are.
- What Wyrm stores about you is what you can already see in the app: your
  names, your picture, your best score, your kills, and anything you typed into
  chat.
- Nothing is sold. Nothing is shared with advertisers. There are no adverts and
  no tracking libraries in this app.
- You can delete your account from inside the app, and it deletes.

---

## Signing in

Your password is sent once, over an encrypted connection, to Wyrm's own server
when you create the account or sign in. The server keeps only a salted hash of
it, never the password itself. What the app keeps afterwards is a session token,
and it lives in the iPhone **Keychain**, not in ordinary app storage.

---

## What Wyrm knows about you

### What you give it

| What | Why |
| --- | --- |
| Your username | It is the `@handle` other players find you by, and how you sign in |
| Your display name | Shown on your profile and in lists |
| Your profile picture | Your avatar, only if you add one |

- **An in-game name**, printed over your snake in the arena.
- **A short bio**, if you write one.

### What playing produces

- Your **highest score** and **total kills**, and a record of each finished run
  so those totals can be recounted rather than trusted blindly.
- **Messages** you send in global chat or in a direct thread, and **reports** you
  file about someone else's message.
- **Who you follow** and **who you have blocked**.
- **Name changes**, so the limit on how often you may rename is counted from
  something a reinstall cannot reset.
- If you choose Voice Chat, a separately verified **email address** is stored
  encrypted for voice access and abuse prevention. Other players and the
  operator dashboard never see it.
- Voice rooms keep creator, membership, moderation and call-duration metadata.
  Wyrm does not store the audio, record it or transcribe it.

### What stays on your phone and never leaves it

- Every game setting: controls, layout, colours, sizes, your skin and theme.
- Your Team Mode credentials, if you use Team Mode. These are held in the iOS
  Keychain and are sent only to the team service they belong to, never to
  Wyrm's server.
- Developer logs, only if you turn Developer Mode on. They expire after seven
  days and leave the phone only if you share them yourself.
- A backup file, only if you make one. It holds settings, buttons, skin, theme
  and notification choices — never your password, session or Team credentials.

---

## Who else is involved

Wyrm talks to outside services, and it is worth knowing which is which:

1. **Slither's public arena directory**, to list which arenas exist and how busy
   they are, and then the arena itself while you play. This is the game you are
   playing; your snake's position goes to the arena server the way it does in
   any online game. Wyrm sends no account information there — the arena knows
   only the name over your snake.
2. **The team service**, only if you turn on Team Mode, and only with the
   credentials you entered yourself.
3. **Brevo**, only to deliver the Voice Chat verification code that Wyrm's
   backend generated.

Wyrm's own server is a machine run by the author. It is not a cloud
account with an analytics dashboard attached.

## What Wyrm does not do

- No advertising, and no advertising identifiers.
- No analytics or crash-reporting service. Nothing counts your sessions.
- No location or contacts, and no photo library scanning. The app asks for a
  photo only when you pick one, and only that photo.
- No voice recording and no transcription.
- No selling, renting or sharing of your data. There is nobody to sell it to.

## Other players see

Your display name, your username, your in-game name, your avatar, your bio, your
best score and your kills, and anything you posted in global chat. Your email
address is never shown to another player.

## Deleting your account

Profile → Edit profile → Delete account. It removes your account, your photograph and your bio
outright. Messages you already sent stay where they are but are attributed to
"deleted player" — the same way a deleted account works anywhere that people
have already replied to you. Creating an account again starts a new, empty
account; it does not bring the old one back.

## Children

Wyrm is not built for children under 13, and accounts are not knowingly created
for them.

## Changes

If this document changes in a way that affects what is collected or who sees it,
the app will ask you to read it again rather than quietly updating the date.

## Asking

Write to **ommanav.mail@gmail.com**.
