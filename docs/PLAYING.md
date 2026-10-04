# Playing DIAMOND IN THE ROUGH

## Start playing

Double-click DiamondInTheRough.exe. No browser or Godot installation is needed.
Keep the supplied build files together if copying the game to another folder.

Choose New game for a fresh mountain, or Continue to return to your claim.
New game replaces the current save. Settings offers mouse sensitivity, field
of view, audio, proximity voice and fullscreen.

The mountain grew much bigger in this build, so claims from earlier builds
cannot be carried over: Continue stakes a fresh claim on the new mountain the
first time you play it. The old save file is kept next to the new one with
`.v2.old` added to its name.

The first solo or hosted session starts a seven-step guide at the camp. It
teaches movement, mining ore, selling, buying the steel pickaxe, digging out a
fossil, close inspection and safe storage. Use How to play to replay or skip
it. Completed guidance stays completed on your PC. Replays direct full hands to
safe storage. A mountain with every find already dug out instead shows help for
the stored finds, preserving your progress.

Your first shift: walk to the mountain behind the camp, aim at the rock and hold
left click. Rock flecked with colour is ore; mining it puts it straight into your
satchel. Carry the satchel to the Scrap Exchange and press E to sell. The
steel pickaxe costs $60. The HUD and Tab journal show your next goal, your
satchel, ore prices and the diamond objective.

## Controls

```text
WASD                 Move
Mouse                Look; rotate the held object during inspection
Shift / Space        Move faster / jump
E                    Pick up a find, use a station or buy a displayed tool
Left mouse (hold)    Mine with the pickaxe or drill, or throw the selected explosive
Right mouse          Enter or finish close inspection
Mouse wheel          Cycle through carried finds
                     Empty hands at tray: change storage page
Ctrl + mouse wheel   Zoom the object during inspection
Q                    Drop the selected find
1                    Pickaxe (becomes the steel pickaxe or power drill once bought)
2 / 3 / 4            Dynamite / TNT / Mountain Buster, once bought
C                    Keep the selected fossil or curiosity on display
Tab / Esc            Journal / pause menu
V                    Hold to talk to nearby players in co-op
M                    Mute / unmute your microphone
G                    Polishing foam prank; aim at a friend
R                    Give a friend your selected find as a wrapped present
H                    Cycle available hats
```

Aim at a nearby friend and left click to tip your carried finds over them.
Pranks preserve the diamond, equipment and shared money.

## The mountain

The mountain is about 144 metres across and rises about 70 metres from the
valley floor: grassy foothills rise into bare rock, cliffs, three rocky
shoulders and a snowy summit. You can walk up
the lower slopes; the steep upper faces need digging or blasting. Each swing of
the pickaxe breaks away about a metre of rock: soil near the surface, then
stone. Deep inside is granite, which the old pickaxe cannot break, and the
thick interior rests on unbreakable bedrock. The crosshair prompt names the
rock you are aiming at, its ore price, whether your tool can break it, and
your progress. Hold left click to keep swinging; chips fly off with each hit.

Ore grows in veins and gets richer the deeper you dig:

```text
Coal $2 · Tin ore $3 · Copper ore $4 · Iron ore $6       first 4 m
Silver ore $11 · Turquoise $15 · Gold nugget $20          4 to 12 m down
Topaz $24 · Amethyst $28 · Opal $33                       12 to 22 m down
Emerald $38 · Sapphire $45 · Platinum ore $50             22 to 32 m down
Ruby $55                                                  deepest, near the core
```

Each band also holds some ore from the bands next to it. Fourteen kinds of ore
fill about 18% of the mountain.

Ore goes straight into your satchel. A full satchel will not take more ore:
sell it at the exchange first. Explosions that find more ore than you can
carry lose the excess, and the message says how much.

Pale seams hold fossils and other curiosities. When you break one, the find
pops out and drops onto the rock
below. Walk over it to pick it up, or aim at it and press E. Finds never get
destroyed: if the rock beneath them is mined away, they settle further down.

## The camp outfitter

Each tool has its own display with an attached name-and-price card. Point at
the display and press E to buy it; the card changes to OWNED. No buying menu
opens.

```text
$60    Steel pickaxe: mines twice as fast and cuts through granite.
$110   Big satchel: carry 90 ore and 10 finds (instead of 30 and 4).
$150   Assay loupe: every ore sells for 25% more at the exchange.
$180   Dynamite: press 2, left click to throw. Blasts a 2.4 m crater.
$300   Ore magnet: pulls loose finds within 7 m into your hands.
$420   Power drill: hold left click to drill through rock at speed.
$750   TNT: press 3 to throw. Blasts a 3.9 m crater.
$1000  Treasure sonar: pings the buried diamond and fossils within 16 m
       through solid rock.
$2400  Mountain Buster: press 4 to throw. Blasts a 6.5 m crater.
```

Thrown charges stick where they land and burn their fuse before exploding.
Each explosive needs a few seconds to prepare between throws; the HUD shows
when it is ready. Stand back: the blast throws nearby players clear. Blast
ore goes to the thrower's satchel, and released finds drop into the crater.

## Finding the diamond

There is exactly one diamond in the mountain and no fakes. It is buried in the
core, at least 28 metres below the surface and just above the bedrock. Its
block is the only glittering kimberlite in the mountain: when the crosshair
prompt says "Glittering kimberlite", you have found it. The treasure sonar
shows it through 16 metres of rock. Dig or blast your way down; explosions
never destroy it.

At the inspection tray, E places your carried finds into storage. Aim directly
at a find to pick it back up. With empty hands, use the wheel over the tray or
press E on its tabletop to change storage pages. Right-click a held find to
rotate and inspect it. The diamond cannot be sold: the exchange always routes
it safely to the tray.

Carry the diamond to the Certification Bench at the foot of the mountain, aim
at the bench and press E. It earns the ending and a $1,000 discovery grant. You
can keep mining afterwards.

Press C to display a fossil or curiosity. The Specimen Collection also shelves
carried fossils when used. New collection entries earn a $12 museum grant and
personal cosmetic rewards. Selling a curiosity instead is your choice.

## Host and join: up to four players

On the host PC, choose Co-op, then Host game. The default UDP port is 24680.
This continues the host's saved mountain. For a fresh shared run, start a new
game first, return to the title, then choose Co-op and Host game.

On another PC, choose Co-op, enter the host's local IP address, use the same
port and choose Join game. Allow the game through Windows Firewall on the
network being used. The host must stay running; money, purchases, finds and
every bit of mined rock are shared, and each player carries their own satchel. A
player who leaves has their satchel ore sold into the shared funds. There are
no AI teammates.

For co-op on one PC, open two separate copies of the executable. Host in the
first window, then join 127.0.0.1 on port 24680 in the second. Use Esc to release
the cursor before switching windows. Additional local clients can join the
same way, up to four players total.

Direct connections require a reachable host and an allowed UDP port. Internet
hosting may require router port forwarding. There is no internet matchmaking,
NAT traversal service or relay. Steam invites are not implemented.

## Proximity voice chat

Voice is enabled by default and uses push-to-talk. Hold V while mining on a
shared claim to speak, and release it to stop. Press M to mute or unmute your
microphone. The HUD shows your voice status; nearby speaking players have an
indicator above their hats. Solo play and menus do not transmit microphone audio.

Voices come from each player's location. Speech stays at full volume within
2 metres, gets quieter as you move apart, and stops at 12 metres. Walk closer
to continue the conversation. Everyone on the claim must use this new build.

In Settings, choose your microphone and use Refresh after connecting a new
device. Microphone gain adjusts your input; Nearby voice volume adjusts voices
you hear. Master audio also affects received voices. Enable proximity voice
controls both sending and receiving. Mute microphone stops only your own voice.
The input meter reflects your microphone level when talking in co-op.

If the HUD says No mic signal, check the selected microphone, return to the game
and hold V while speaking. Check Windows microphone privacy settings and enable
microphone access for desktop apps. Use headphones to keep received voices and
game sound out of your mic. This prototype has no echo cancellation.

Voice is live only. The game does not save recordings or include audio in saves.

## Save and recovery

Solo and host play saves money, equipment, collections, all mined rock,
find locations, the host's satchel and the diamond's generated location.
Purchases and sales save immediately; mining is saved every few seconds and
whenever you leave. The client does not overwrite its own save with the
host's world. The normal save is:

%APPDATA%\Godot\app_userdata\DIAMOND IN THE ROUGH\rough_workshop.json

Carried finds return to the inspection tray when a save loads or their owner
disconnects. The diamond cannot be sold accidentally: the exchange redirects it
to the tray. Dropped finds remain recoverable. Use the Lost & Found bell by the
entrance, or Recover lost finds in the Tab journal. The journal's Return to
solid ground option brings you back to camp if you dig yourself into a hole.

## Screen sizes

Resize the window or use fullscreen in Settings. The HUD and dialogs adapt to
the current window dimensions, including 4:3, 5:4 and ultrawide proportions.
Text retains its proportions; long settings and help pages scroll vertically.

## Prototype scope

The mountain, camp, materials and sound effects are generated for this
prototype. Digging works on about 228,000 cells of 1 metre under a smooth
rock surface; only the parts touched by mining or a blast are rebuilt. There
are no cave-ins: unsupported rock stays where it is. Explosions remove rock
within a sphere and do not damage players. Prank reactions use brief
physics/animation responses rather than full character ragdolls.

This build contains no Steamworks integration. A production release still needs
a Steam App ID, SDK integration and credentials/configuration for invitations,
achievements and release services. Local save and host/join systems provide the
prototype foundation. Engine/source files are included for continued work;
open project.godot in Godot 4.6.2 to edit the project.

Proximity voice uses a simple mu-law codec. Production Opus voice encoding and
Steam voice/networking services are not implemented.
