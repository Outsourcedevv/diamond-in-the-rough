# Playing DIAMOND IN THE ROUGH

## Start playing

Double-click DiamondInTheRough.exe. No browser or Godot installation is needed.
Keep the supplied build files together if copying the game to another folder.

Choose New game for a fresh mountain, or Continue to return to your claim.
New game replaces the current save. Settings offers mouse sensitivity, field
of view, audio, proximity voice and fullscreen.

Saves from the earlier scree-sorting builds cannot be carried into the
mountain: Continue starts a fresh mountain the first time you play this build.

The first solo or hosted session starts a seven-step guide at the camp. It
teaches movement, mining ore, selling, buying the steel pickaxe, digging out a
crystal or fossil, close inspection and safe storage. Use How to play to replay
or skip it. Completed guidance stays completed on your PC. Replays direct full
hands to safe storage. A mountain with every find already dug out instead shows
help for stored candidates and certification, preserving your progress.

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
F                    Apply a fake label to your held find or a friend's finds
G                    Polishing foam prank; aim at a friend
R                    Give a friend a clear crystal as a wrapped present
H                    Cycle available hats
```

Aim at a nearby friend and left click to tip your carried finds over them.
Pranks preserve the diamond, equipment and shared money.

## The mountain

Grassy foothills rise into bare rock, cliffs and a snowy summit. You can walk up
the lower slopes; the steep upper faces need digging or blasting. Each swing of
the pickaxe breaks away about a metre of rock: soil near the surface, then
stone. Deep inside is granite, which the old pickaxe cannot break, and the
thick interior rests on unbreakable bedrock. The crosshair prompt names the
rock you are aiming at, its ore price, whether your tool can break it, and
your progress. Hold left click to keep swinging; chips fly off with each hit.

Ore grows in veins and gets richer the deeper you dig:

```text
Coal $2 · Copper ore $4 · Iron ore $6       near the surface
Silver ore $11 · Gold nugget $20            a few metres down
Amethyst $28 · Emerald $38                  deep
Sapphire $45 · Ruby $55                     deepest, near the core
```

Ore goes straight into your satchel. A full satchel will not take more ore:
sell it at the exchange first. Explosions that find more ore than you can
carry lose the excess, and the message says how much.

Glittering white veins hold crystals; pale seams hold fossils and other
curiosities. When you break one, the find pops out and drops onto the rock
below. Walk over it to pick it up, or aim at it and press E. Finds never get
destroyed: if the rock beneath them is mined away, they settle further down.

## The camp outfitter

Each tool has its own display with an attached name-and-price card. Point at
the display and press E to buy it; the card changes to OWNED. No buying menu
opens.

```text
$60    Steel pickaxe: mines twice as fast and cuts through granite.
$110   Big satchel: carry 90 ore and 10 finds (instead of 30 and 4).
$150   Loupe & lamp: clearer facet, inclusion and optical inspection clues.
$180   Dynamite: press 2, left click to throw. Blasts a 2.4 m crater.
$300   Ore magnet: pulls loose finds within 7 m into your hands.
$420   Power drill: hold left click to drill through rock at speed.
$750   TNT: press 3 to throw. Blasts a 3.9 m crater.
$1000  Crystal sonar: pings buried crystal veins within 12 m through rock.
$2400  Mountain Buster: press 4 to throw. Blasts a 6.5 m crater.
```

Thrown charges stick where they land and burn their fuse before exploding.
Each explosive needs a few seconds to prepare between throws; the HUD shows
when it is ready. Stand back: the blast throws nearby players clear. Blast
ore goes to the thrower's satchel, and released finds drop into the crater.

## Finding the diamond

The one genuine diamond is buried deep in the mountain's core, hidden among
about 150 clear quartz crystals that look identical in the rock. Dig or blast
your way down and collect clear crystals as you go.

At the inspection tray, E places your carried finds into storage. Aim directly
at a stone to pick it back up. With empty hands, use the wheel over the tray or
press E on its tabletop to change storage pages; every candidate stays
accessible. Right-click a held stone to rotate and inspect it. Look for
fast-clearing breath mist, sharp facet junctions, no trapped bubbles, and a
point behind the stone lost in haze. The loupe adds the decisive edge and
inclusion clues. Clear crystals cannot be sold: the exchange always routes
them safely to the tray.

Bring a promising held crystal to the Certification Bench at the foot of the
mountain. Aim at the bench and press E for each of its three tests. The final
test gives the verdict. Imitations return unharmed; the genuine diamond earns
the ending and a $1,000 discovery grant. You can keep mining afterwards.

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
disconnects. The diamond cannot be sold accidentally: clear crystals are
redirected to the tray. Dropped finds remain recoverable. Use the Lost & Found
bell by the entrance, or Recover lost finds in the Tab journal. The journal's
Return to solid ground option brings you back to camp if you dig yourself into
a hole. Recovery also resets an unfinished certification sequence.

## Screen sizes

Resize the window or use fullscreen in Settings. The HUD and dialogs adapt to
the current window dimensions, including 4:3, 5:4 and ultrawide proportions.
Text retains its proportions; long settings and help pages scroll vertically.

## Prototype scope

The mountain, camp, materials and sound effects are generated for this
prototype. Digging works on about 29,000 cells of 1 metre under a smooth
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
