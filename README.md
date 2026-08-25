<h1 align="center">
  <br>
    <img src="icons/production/chudder_store_icon.png" alt="Chudder" width="200">
  <br>
  Chudder
  <br>
</h1>

<h4 align="center">An opinionated fork of <a href="https://github.com/DonutWare/Fladder">Fladder</a> — a cross-platform Jellyfin client built with <a href="https://flutter.dev/" target="_blank">Flutter</a>.</h4>

<p align="center">
  <a href="#why-this-fork-exists">Why this fork exists</a> •
  <a href="#what-chudder-adds">What Chudder adds</a> •
  <a href="#design-choices">Design choices</a> •
  <a href="#download">Download</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#credits">Credits</a> •
  <a href="#license">License</a>
</p>

<div align="center">

  [![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-%23FE5196?logo=conventionalcommits&logoColor=white)](https://conventionalcommits.org)
  [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

</div>

## Why this fork exists

Fladder is a genuinely good Jellyfin client, and this fork exists because of that
rather than in spite of it. I use it every day, on a desktop and a phone and a TV,
and every day I noticed small things I wanted to work differently. Not bugs — taste.
The kind of thing that is nobody's job to fix because it is only wrong for me.

So Chudder is my perfect version of it: an app I change whenever I want it to feel
different, without asking anyone whether my preference is the right one. Some of
those changes are opinionated to the point of being unmergeable upstream. Some are
features I wanted badly enough to build. Most are the hundred small adjustments that
add up to an app feeling like it was made for you, because it was.

If your taste happens to line up with mine, you are very welcome here.

## What Chudder adds

The two big ones, neither of which exists upstream:

### Casting

Chudder casts on every platform it runs on, through whichever protocol the device on
your shelf actually speaks:

* **Chromecast** — native Google Cast on Android and iOS, a pure-Dart CASTV2 sender on
  Windows, macOS and Linux, and the Cast Web Sender on Chromium browsers. Plays through
  the Jellyfin receiver where it can and a default-receiver path where it can't.
* **AirPlay** — the real system picker on iOS and macOS, with subtitle and audio track
  switching rather than a video stream you cannot change.
* **DLNA / UPnP** — direct play with on-demand transcode when the renderer can't handle
  the subtitles, audio track or bitrate you asked for.

It starts from what you were already watching — current track, current quality, current
position — and drops the player into a remote control once connected. It will also adopt
a stream already running on a receiver instead of restarting it, and it hides audio-only
renderers when you are casting video. There is a "why can't I find my device?" panel in
the picker, because discovery is the part that always goes wrong.

### SyncPlay

Watching the same thing at the same time as someone who is not in the room:

* Latency-adaptive drift correction with ping reporting and a warm-up period, tuned for
  people watching over the internet rather than across a living room.
* A persisted per-user playback offset, so if your stream is reliably a second and a
  half behind someone else's, you set it once.
* Optimistic local loading on next/previous episode, so changing episode in a group does
  not stall everyone on a spinner.
* A group indicator and controls that are reachable from inside the player and from every
  screen, not just the one that thought to offer them.

### On a television

Fladder has a lean-back mode. What it did not have was a player you could actually drive
from a remote: the arrow keys were bound to volume and seeking through a handler that runs
before focus is consulted at all, so they never reached the controls. The buttons were on
screen and unreachable.

* **The controls take the pad.** The selection lands on play/pause, because it is the one
  control anybody is looking for. The scrubber and the volume each claim an axis while
  selected — the scrubber walks with left and right, the volume with up and down — and the
  other axis still carries you off the control.
* **Scrubbing that suits the runtime.** Holding a direction accelerates in proportion to
  what is playing: a step that crosses a two-hour film in a sensible number of presses
  would fly straight past the end of a twenty-minute episode. The bar moves and the clock
  counts toward where you are going, and one seek is issued when you stop rather than one
  per press.
* **Every dialog has a way out.** At a desk you dismiss one by clicking beside it or
  pressing Escape. A remote has neither, so a dialog with no visible close is a dead end
  whose only exit is killing the app. They all have one now — in the title row where there
  is a title row, on the card's own corner where there is not.
* **Nothing sits out of reach.** The next-episode card, the queue, the subtitle and audio
  pickers, SyncPlay and Cast. Pressing up from the top of a page reaches the chrome, and
  focus stays inside whatever is open rather than wandering onto the page behind it.
* **No small player.** A television has nowhere for a floating window to go, so minimize
  and picture-in-picture are not offered there.

### And a good deal else

**Your headphones can run the show.** Press play on a headset, or the play key on a
keyboard, while the next-up card is on screen and the next episode starts. Press it while
a Skip Intro or Skip Credits button is showing and it skips. With neither prompt up it
plays and pauses like it always did. So you can get through the whole gap between
episodes — credits, intro, next one rolling — without reaching for the device or even
looking at it. This is the feature I miss most when I use anything else.

**Playback follows you around.** Shrink the player into a small window you can drag,
resize and pinch, and carry on browsing underneath it. On Windows the transport buttons
turn up in the taskbar preview; on Android it takes audio focus properly instead of
talking over whatever else is playing.

**Studios are actual pages.** Click a studio and you get a grid of what they made and
what you haven't seen yet, rather than "not implemented yet".

**Search that forgives you.** Type a name and you get the person with four films in your
library before the one with a single credit. Misspell a title and it still finds it. Come
up empty and it suggests something to try instead.

**Settings search.** Across every settings page at once, because I could never remember
which page a thing lived on.

## Design choices

The parts where Chudder deliberately disagrees with upstream:

**Chrome that stays put.** SyncPlay and Cast start sessions that outlive whatever screen
you are on — you can join a group or connect to a device before you have chosen anything
to play. So they live in the app's chrome, in the same corner on every overview screen,
rather than on the one screen that happened to offer them.

**Controls that shed rather than overflow.** The player's bottom bar works to a budget.
Play/pause is the only button it will not part with; everything else bids for the
remaining width in order of importance, and a narrow window drops the least useful
buttons instead of running off its own edge. Anything it drops is still one tap away in
the options sheet.

**One shape per row.** Posters are one shape, scroll arrows sit at the ends of the row
and on the artwork rather than floating beside it, and banners are not cropped to fit a
grid they were never meant for.

**Show pages you don't get lost in.** This one came straight out of frustration. I kept
opening a series, going into a season, into an episode, and then having no idea how to
get back to the season I actually wanted — or how to tell where I was. So moving between
seasons and episodes is direct now, the header takes up far less room, a phone opens the
page at the title instead of somewhere below the fold, and the things you can actually
watch come first.

**If it is playing, you can see it.** The player is shown either full screen or as a
minimized window or bar — and it was possible to reach a state that showed neither, with
media playing on and nothing to look at or press. Rather than guard every path that opens
the player, the app watches for the combination that cannot be right and falls back to the
minimized player.

**Leaving a group is not leaving the film.** Ending a SyncPlay session used to close the
player out from under you. It keeps playing; you are simply watching on your own from
there.

**Notices in one place.** They used to arrive from whichever edge suited the layout — the
right on a desktop, the full width of a phone — so the same message turned up somewhere
different depending on what you happened to be holding. Top centre everywhere now, built
from the same surfaces as the rest of the app.

**Icons that read as what they do.** A handful of the originals never quite landed for me
— I would look at one and have to think about what it meant, which is one thought too
many. Those got changed. Entirely a matter of taste, and exactly the sort of change that
is easier to make in your own fork than to argue for in someone else's.

**Its own look.** A blue accent, art-derived backgrounds, and a drawn cheese wedge for an
icon. Chudder is a distinct app and should not be mistaken for Fladder at a glance —
that matters both for you and out of respect for the original.

> **Note**
> Screenshots here are pending — the ones in this repository are still Fladder's and
> would misrepresent what the app looks like now.

## Download

Builds are produced from this repository's [releases page](https://github.com/JenteJan/Chudder/releases).

> **Warning**
> Chudder is a personal fork. It tracks upstream Fladder but is not tested anywhere near
> as broadly, and it is primarily exercised on Windows and Android. If you want the
> stable, widely-tested option, use [Fladder](https://github.com/DonutWare/Fladder) — it
> is excellent and you will be in good hands.

> **Warning**
> (Windows) Some Flutter applications are flagged as false positives by Windows Defender.
> See [this upstream issue](https://github.com/DonutWare/Fladder/issues/197#issuecomment-2568906874)
> for background.

## Contributing

Contributions are genuinely welcome. This is an opinionated fork, but opinionated does
not mean closed.

### 🐛 Reporting bugs

Open an issue and I will do my best to fix it. Please check it has not already been
reported, and include the steps to reproduce it — that is the part that decides whether
a bug gets fixed this week or this month.

If the bug also exists in upstream Fladder, it is worth reporting it
[there](https://github.com/DonutWare/Fladder/issues) too; fixes that belong upstream I
will try to send upstream.

### 🚀 Pull requests

Pull requests are welcome. For anything large, open an issue first so we can agree on the
shape of it before you spend an evening on it — this fork has strong opinions about how
things should feel, and it would be a shame to find that out at review time.

Keep pull requests focused on one thing. It makes review faster and kinder.

### What I commit to

* **Fixing what gets raised.** Issues opened here get my honest best effort.
* **Staying in line with the official repo.** I track upstream Fladder and merge its
  changes in rather than drifting away from it. Bug fixes I make that are not
  taste-specific I will offer back upstream.
* **Fixing what I run into.** Most of what is in here started as something that annoyed
  me during ordinary use. That will continue.

## Credits

Chudder is a fork of **[Fladder](https://github.com/DonutWare/Fladder)** by
[**DonutWare**](https://github.com/DonutWare) / [PartyDonut](https://github.com/PartyDonut).

Essentially all of the hard work is theirs. Fladder is a polished, thoughtfully built
Jellyfin client, and everything here rests on years of it. This fork exists because the
foundation was good enough to be worth having opinions about. Thank you — sincerely.

If you want to support the work this is built on, the sponsor links on this repository go
to **the Fladder authors, not to me**. That is deliberate.

This software also uses:
- [Flutter](https://flutter.dev/)
- [Jellyfin](https://jellyfin.org/) — the server this is a client for

## License

Chudder is a modified version of Fladder and is licensed, as Fladder is, under the
**GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full text.

The files in this repository have been modified from the Fladder originals; the commit
history records what changed and when.
