# Locked — iOS app

The `Locked.dc.html` prototype, rebuilt as a native SwiftUI app: seven screens,
real timers, a Lock Screen Live Activity, system-level app blocking through
Apple's Screen Time API, and a pod that is other actual people over the network.

## Run it

```bash
open "ios/Locked.xcodeproj"
```

⌘R. Signed with team `2MUHC6TNGW`; the app and all three extensions provision
automatically. iOS 17+, portrait, dark only.

Four targets:

| Target | What it is |
|---|---|
| `Locked` | the app |
| `LockedWidgets` | Live Activity — Lock Screen card + Dynamic Island |
| `LockedMonitor` | DeviceActivityMonitor — re-arms the shield when the app is dead |
| `LockedShield` | the screen you hit when you open a blocked app |

They share `Shared/` (palette, formatters, session snapshot, activity attributes)
and the app group `group.com.aaryanpanchal.locked`.

## First run

The app opens on onboarding, and it does real work: an account, then a pod, then
your stake. There is no way to end up in the app with an imaginary pod.

1. **Start the server** — `server/run.sh` (push needs your APNs key, see
   [server/README.md](../server/README.md)):

   ```bash
   export APNS_KEY_PATH=~/Downloads/AuthKey_7MGUNZZL9M.p8
   export APNS_KEY_ID=7MGUNZZL9M
   server/run.sh
   ```

2. **Point the app at it.** The address differs by where the app is running:

   | Running on | Server address |
   |---|---|
   | Simulator | `http://localhost:8787` (prefilled) |
   | Your iPhone, same Wi-Fi | `http://10.0.0.80:8787` |
   | Anyone else, anywhere | a tunnel: `cloudflared tunnel --url http://localhost:8787` |

   On a phone, `localhost` means *the phone* — the app says so if you try it.

3. **Sign in with Apple**, then create a pod (you get a 6-character invite code)
   or join one with somebody else's.

Accounts follow your Apple ID: deleting the app doesn't lose your pod, and
signing in on a second device resumes the same account.

### Dev mode

There are no invented people in the app. But **Settings → Dev mode** switches on
a cast of four actors who lock in, fold and answer your unlock requests on a
timer — for demos and testing. It's off by default, can't be turned on while
you're in a real pod, and nothing it produces is ever sent to a server.
Onboarding offers it too, for looking around before you have a server.

Turning it off empties the pod, because that's the truth.

## What's real

| | Status |
|---|---|
| Sessions, countdown, streaks, stakes, standings | Real, persisted, survives force-quit |
| Live Activity (Lock Screen + Dynamic Island) | Real on device — see the caveat below |
| System-level app blocking | Real — Family Controls entitlement granted for development |
| Accounts | Sign in with Apple, verified server-side against Apple's keys |
| Pod: members, feed, unlock requests, verdicts | Real over the network. Empty until you have one — no stand-ins |
| Hours finished offline | Queued locally and uploaded on the next sync |
| **Push, with Approve/Deny on the notification** | **Real — verified end to end with the app terminated** |
| Hours and streaks | Derived server-side from session records, not self-reported |
| Account deletion, leaving, removing a member | Real (deletion is an App Store requirement) |
| Dev mode | Opt-in simulated pod for demos, off by default |
| Tests | 31 server + 32 app, all green |

### Live Activity caveat

ActivityKit accepts the request and `chronod` registers the activity, but **the
iOS 26.5 simulator doesn't render third-party Live Activities** — its renderer
never produces the archive (`Content load failed: unable to find or unarchive
file`, even for a one-line `Text` view). Confirm it on your phone: start a
session, then lock the screen. On device the countdown ticks locally from the
date range, so it stays correct with zero updates and no push.

### Screen Time

First session on device will prompt for Screen Time access. Grant it, then
**Settings → Real blocking → Pick the real apps** (Apple's own picker — apps can
never see your app list). After that the block is enforced by iOS, not by
willpower, and `LockedShield` shows your goal, time left and who's watching on
the block screen.

Two limits worth knowing:

- `DeviceActivitySchedule` rejects windows shorter than 15 minutes, so the
  monitor extension only arms for sessions ≥ 15 min. Below that the app is alive
  for the whole session anyway.
- The entitlement in this build is the **development** one. Shipping to the App
  Store needs Apple's distribution approval:
  <https://developer.apple.com/contact/request/family-controls-distribution>

## Tests

```bash
server/.venv/bin/python server/test_server.py

xcodebuild test -project ios/Locked.xcodeproj -scheme Locked \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The app tests inject a clock and a storage path into `AppState`, so streaks,
week rollover, folding and completion are checked across day boundaries without
waiting for one. `PushHandlingTests` covers what the notification's buttons do.

## What to add next

1. **Rate limiting** on the server. There is none, and `POST /v1/register` needs
   no auth — fine on your Wi-Fi, not fine on a public URL.
2. **HTTPS and a permanent home.** A Cloudflare tunnel is fine for testing with
   friends; Fly.io with a volume is the small permanent version. Once it's on a
   real host, drop `NSAllowsLocalNetworking` from [project.yml](project.yml).
3. **Invite links** instead of typing six characters — a universal link that
   opens the app straight into the pod.
4. **The real typefaces.** Cormorant Garamond over Lora: drop the `.ttf` files
   in, add `UIAppFonts` to the `info:` block in [project.yml](project.yml), and
   change the two functions in [Theme.swift](Locked/Theme.swift).
5. **A ShieldAction extension** if you want the block screen's button to do
   something other than dismiss — "ask the pod" straight from there.

## Layout

```
ios/
  project.yml              XcodeGen source of truth — edit this, not the .xcodeproj
  Shared/                  compiled into every target
    Palette.swift          colours, type scale, formatters
    LockedShared.swift     app group, SessionSnapshot the extensions read
    LockedActivity.swift   ActivityAttributes (excluded from the Screen Time targets)
  Locked/
    LockedApp.swift        entry point
    PushRegistrar.swift    UIApplicationDelegate: device tokens, notification responses
    Store.swift            AppState: timers, rollover, streaks, sync, push handling
    Models.swift           Session, PodMember, FeedEvent, UnlockRequest, Profile
    PodService.swift       protocol + simulated pod + HTTP client + Apple pairing
    Blocking.swift         Screen Time wrapper and DeviceActivity schedule
    LiveActivityController.swift
    Notifications.swift    local notifications, categories, actions
    Views/                 one file per screen, plus Components.swift
  LockedWidgets/           Live Activity
  LockedMonitor/           DeviceActivityMonitor extension
  LockedShield/            ShieldConfiguration extension
  LockedTests/             32 unit tests
server/                    the pod server — see server/README.md
```

After adding files or changing build settings:

```bash
cd ios && xcodegen generate
```
