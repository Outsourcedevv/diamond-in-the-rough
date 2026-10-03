# Playing DIAMOND IN THE ROUGH

## Start playing

Double-click DiamondInTheRough.exe. No browser or Godot installation is needed.
Keep the supplied build files together if copying the game to another folder.

Choose New game for a fresh save, or Continue to return
to your existing operation. New game replaces the current workshop
save. Settings offers mouse sensitivity, field of view, audio, proximity voice
and fullscreen. Existing workshop saves continue to work with this build.

The first solo or hosted session starts a seven-step guide inside the yard.
It teaches movement, scooping or picking, close inspection, selling, buying
a physical scoop, safe storage and returning to search. Use How to play to
replay or skip it. Completed guidance stays completed on your PC.
Replays direct full hands to safe storage. An already searched mountain instead
shows help for stored candidates and certification, preserving your progress.

Your first shift: climb the scree, inspect interesting finds, then take a
batch to the Scrap Exchange and press E to sell it. Hidden cash, metal and
collectibles fund early progress. The bigger scoop costs $70. The HUD and Tab
ledger show the next upgrade, your collection and the diamond objective.

## Controls

```text
WASD                 Move
Mouse                Look; rotate the held object during inspection
Shift / Space        Move faster / jump
E                    Pick up a find, scoop a patch, use a station or buy a model
Left mouse           Scoop a batch or use the equipped tool
Right mouse          Enter or finish close inspection
Mouse wheel          Cycle through carried objects
                     Empty hands at tray: change storage page
Ctrl + mouse wheel   Zoom the object during inspection
Q                    Drop the selected object
1 / 2 / 3 / 4        Scoop / bare hands / purchased vacuum / purchased scanner
C                    Keep the selected collectible or oddity on display
Tab / Esc            Workshop ledger / pause menu
V                    Hold to talk to nearby players in co-op
M                    Mute / unmute your microphone
F                    Apply a fake label to your held find or a friend's batch
G                    Polishing foam prank; aim at a friend
R                    Give a friend a promising stone as a wrapped present
T                    Reverse-conveyor prank; requires the conveyor and a friend
H                    Cycle available hats
```

Aim at a nearby friend and use the scoop to pour a batch on them, or the vacuum
to gather loose objects around their workstation. Pranks preserve the diamond,
equipment and shared money. Washing removes foam.

## The workshop

At the equipment counter, each upgrade has its own model and an attached
name-and-price card. Point at the item and press E to purchase it. Installed
items change their price card to INSTALLED; no buying menu opens.

```text
$70   Bigger scoop: carrying capacity increases from 3 to 9.
$100  Sorting trays: 14-object capacity and expanded candidate storage.
$145  Loupe + lamp: clearer facet, inclusion and optical inspection clues.
$180  Washing station: cleans held/tray discoveries; clean sales earn 60% more.
$330  Sorting machine: processes 18 objects from the last selected pile sector.
$440  Vacuum: gathers loose discoveries over a wider area and scoops sectors.
$560  Conveyor: doubles sorting-machine batches to 36 objects.
$850  Scanner: checks a local batch of 24 and flags promising candidates.
```

Choose the machine's source sector by scooping or picking a find there first.
Then visit the Batch Sorter or scanner station and press E. The sorter sells
ordinary material and routes suspicious stones and collectible finds to the
inspection tray. The scanner suggests candidates; it does not certify them.

At the inspection tray, E pours your carried batch into storage. Aim directly
at a stone to pick it back up. With empty hands, use the wheel over the tray or
press E on its tabletop to change storage pages; every candidate stays accessible.
Right-click a held stone to rotate and inspect it.
Look for fast-clearing breath mist, sharp facet junctions, no trapped bubbles,
and a point behind the stone lost in haze. Imitations share some clues: compare
several observations. Manual inspection is available from the beginning.

Bring a promising held candidate to the Certification Bench at the back of the
claim. Aim at the bench and press E for each of its three tests. The final test
gives the verdict. Imitations return unharmed; the genuine diamond earns the
ending and a $1,000 discovery grant. You can keep sorting afterwards.

Press C to display a collectible or oddity. The Specimen Collection also keeps carried
collectibles when used. New collection entries earn a $12 curator grant and
personal cosmetic rewards. Selling an ordinary find instead is your choice.

## Host and join: up to four players

On the host PC, choose Co-op, then Host game. The default UDP port is 24680.
This continues the host's saved workshop. For a fresh shared run, start a new
game first, return to the title, then choose Co-op and Host game.

On another PC, choose Co-op, enter the host's local IP address, use the same
port and choose Join game. Allow the game through Windows Firewall on the
network being used. The host must stay running; money, purchases, finds and
search progress are shared. There are no AI teammates.

For co-op on one PC, open two separate copies of the executable. Host in the
first window, then join 127.0.0.1 on port 24680 in the second. Use Esc to release
the cursor before switching windows. Additional local clients can join the
same way, up to four players total.

Direct connections require a reachable host and an allowed UDP port. Internet
hosting may require router port forwarding. There is no internet matchmaking,
NAT traversal service or relay. Steam invites are not implemented.

## Proximity voice chat

Voice is enabled by default and uses push-to-talk. Hold V while sorting in a
shared workshop to speak, and release it to stop. Press M to mute or unmute your
microphone. The HUD shows your voice status; nearby speaking players have an
indicator above their hats. Solo play and menus do not transmit microphone audio.

Voices come from each player's location. Speech stays at full volume within
2 metres, gets quieter as you move apart, and stops at 12 metres. Walk closer
to continue the conversation. Everyone in the workshop must use this new build.

In Settings, choose your microphone and use Refresh after connecting a new
device. Microphone gain adjusts your input; Nearby voice volume adjusts voices
you hear. Master audio also affects received voices. Enable proximity voice
controls both sending and receiving. Mute microphone stops only your own voice.
The input meter reflects your microphone level when talking in co-op.

If the HUD says No mic signal, check the selected microphone, return to sorting
and hold V while speaking. Check Windows microphone privacy settings and enable
microphone access for desktop apps. Use headphones to keep received voices and
workshop sound out of your mic. This prototype has no echo cancellation.

Voice is live only. The game does not save recordings or include audio in saves.

## Save and recovery

Solo and host actions automatically save money, purchases, collections, object
states and the diamond's generated location. The client does not overwrite its
own workshop save with the host's world. The normal save is:

%APPDATA%\Godot\app_userdata\DIAMOND IN THE ROUGH\rough_workshop.json

Carried items return to the inspection tray when a save loads or their owner
disconnects. The diamond cannot be sold accidentally: suspicious stones are
redirected to the tray. Dropped objects remain recoverable. Use the Lost & Found
bell by the entrance, or Recover lost finds in the Tab ledger. The ledger's
Unstuck option returns you to solid ground. Recovery also resets machinery and
an unfinished certification sequence. Existing saves retain their money,
equipment and diamond identity when loaded into the mountain environment.

## Screen sizes

Resize the window or use fullscreen in Settings. The HUD and dialogs adapt to
the current window dimensions, including 4:3, 5:4 and ultrawide proportions.
Text retains its proportions; long settings and help pages scroll vertically.

## Prototype scope

The workshop, materials and sound effects are generated for this prototype.
The pile contains 720 persistent searchable pieces, plus 1,290 decorative stones
rendered in batches. Only exposed searchable pieces and loose discoveries need
interactive bodies. Machine feeding processes sectors in batches; the conveyor
is a throughput upgrade with an animated workshop model. Prank reactions use
brief physics/animation responses rather than full character ragdolls.

This build contains no Steamworks integration. A production release still needs
a Steam App ID, SDK integration and credentials/configuration for invitations,
achievements and release services. Local save and host/join systems provide the
prototype foundation. Engine/source files are included for continued work;
open project.godot in Godot 4.6.2 to edit the project.

Proximity voice uses a simple mu-law codec. Production Opus voice encoding and
Steam voice/networking services are not implemented.
