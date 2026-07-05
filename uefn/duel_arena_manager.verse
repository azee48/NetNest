
# ============================================================================
# duel_arena_manager.verse
# ----------------------------------------------------------------------------
# 1v1 Duel Arena — full match flow controller for UEFN.
#
# FLOW:
#   Lobby (2 players) -> Loadout Vote Room (15s vote) -> [Weapon Room if both
#   vote Custom] -> 10 Rounds across 3 random zones (storm per zone, real
#   elimination detection) -> Winner announced -> Full reset back to lobby.
#
# ISLAND / DEVICE SETUP REQUIRED (in-editor):
#   - Vote_Timer_Device duration is forced to 15s and Weapon_Timer_Device to
#     30s from Verse in OnBegin (SetActiveDuration).
#   - LB_Player_Counter / Weapon_Player_Counter: set Target Player Count = 2
#     and link their tracking zones (Mut_Lobby / Mut_Weapon). Verse also
#     tracks the mutator zones directly, so either path starts the phase.
#   - Island Settings: enable respawning (players respawn at SPN_Lobby1/2
#     between rounds) and enable "Keep Items on Respawn" so players keep
#     their loadout across rounds (requirement: loadout persists unless
#     changed).
#   - Elim_Manager: configure in-editor (e.g. item drops on elimination).
#     Actual elimination DETECTION is done in Verse via the real
#     fort_character.EliminatedEvent() API, which is the reliable source.
# ============================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Playspaces }
using { /Verse.org/Simulation }
using { /Verse.org/Random }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# All selectable loadouts.
loadout_type := enum { Blitz, BR, Custom, Reload, SameLoot, OG }

duel_arena_manager := class(creative_device) {

    # ------------------------------------------------------------------------
    # LOBBY DEVICES
    # ------------------------------------------------------------------------
    @editable
    SPN_Lobby1 : player_spawner_device = player_spawner_device{}
    @editable
    SPN_Lobby2 : player_spawner_device = player_spawner_device{}
    @editable
    TP_Lobby : teleporter_device = teleporter_device{}
    @editable
    Mut_Lobby : mutator_zone_device = mutator_zone_device{}
    @editable
    LB_Player_Counter : player_counter_device = player_counter_device{}

    # ------------------------------------------------------------------------
    # LOADOUT VOTE ROOM — TELEPORTERS
    # ------------------------------------------------------------------------
    @editable
    TP_LoadoutCenter : teleporter_device = teleporter_device{}
    @editable
    TP_Loadout_Blitz : teleporter_device = teleporter_device{}
    @editable
    TP_Loadout_BR : teleporter_device = teleporter_device{}
    @editable
    TP_Loadout_Custom : teleporter_device = teleporter_device{}
    @editable
    TP_Loadout_Reload : teleporter_device = teleporter_device{}
    @editable
    TP_Loadout_SameLoot : teleporter_device = teleporter_device{}
    @editable
    TP_Loadout_OG : teleporter_device = teleporter_device{}

    # ------------------------------------------------------------------------
    # VOTE FEEDBACK — SWITCHES (turn ON when the loadout receives a vote)
    # ------------------------------------------------------------------------
    @editable
    Switch_Blitz : switch_device = switch_device{}
    @editable
    Switch_BR : switch_device = switch_device{}
    @editable
    Switch_Custom : switch_device = switch_device{}
    @editable
    Switch_Reload : switch_device = switch_device{}
    @editable
    Switch_Sameloot : switch_device = switch_device{}
    @editable
    Switch_OG : switch_device = switch_device{}

    # ------------------------------------------------------------------------
    # VOTE COUNTERS — SCORE MANAGERS (increment once per vote)
    # ------------------------------------------------------------------------
    @editable
    Score_Blitz : score_manager_device = score_manager_device{}
    @editable
    Score_BR : score_manager_device = score_manager_device{}
    @editable
    Score_Custom : score_manager_device = score_manager_device{}
    @editable
    Score_Reload : score_manager_device = score_manager_device{}
    @editable
    Score_Sameloot : score_manager_device = score_manager_device{}
    @editable
    Score_OG : score_manager_device = score_manager_device{}

    # ------------------------------------------------------------------------
    # LOADOUT ITEM GRANTERS
    # NOTE: BR intentionally has no granter (players use map loot) and Custom
    # uses the weapon room instead of a granter.
    # ------------------------------------------------------------------------
    @editable
    IG_Blitz : item_granter_device = item_granter_device{}
    @editable
    IG_OG : item_granter_device = item_granter_device{}
    @editable
    IG_Reload : item_granter_device = item_granter_device{}
    @editable
    IG_Sameloot : item_granter_device = item_granter_device{}

    # ------------------------------------------------------------------------
    # TIMERS
    # ------------------------------------------------------------------------
    @editable
    Vote_Timer_Device : timer_device = timer_device{}
    @editable
    Weapon_Timer_Device : timer_device = timer_device{}

    # ------------------------------------------------------------------------
    # WEAPON ROOM (Custom loadout)
    # ------------------------------------------------------------------------
    @editable
    TP_WeaponRoom : teleporter_device = teleporter_device{}
    @editable
    Mut_Weapon : mutator_zone_device = mutator_zone_device{}
    @editable
    Weapon_Player_Counter : player_counter_device = player_counter_device{}

    # ------------------------------------------------------------------------
    # COMBAT ZONES — SPAWNS + STORM CONTROLLERS
    # ------------------------------------------------------------------------
    @editable
    ZONE1_T1Spawn : player_spawner_device = player_spawner_device{}
    @editable
    ZONE1_T2Spawn : player_spawner_device = player_spawner_device{}
    @editable
    Storm_Zone1 : basic_storm_controller_device = basic_storm_controller_device{}
    @editable
    ZONE2_T1Spawn : player_spawner_device = player_spawner_device{}
    @editable
    ZONE2_T2Spawn : player_spawner_device = player_spawner_device{}
    @editable
    Storm_Zone2 : basic_storm_controller_device = basic_storm_controller_device{}
    @editable
    ZONE3_T1Spawn : player_spawner_device = player_spawner_device{}
    @editable
    ZONE3_T2Spawn : player_spawner_device = player_spawner_device{}
    @editable
    Storm_Zone3 : basic_storm_controller_device = basic_storm_controller_device{}

    # ------------------------------------------------------------------------
    # ELIMINATION
    # Configured in-editor (item drops etc.). Detection itself uses
    # fort_character.EliminatedEvent() below — the real elimination event API.
    # ------------------------------------------------------------------------
    @editable
    Elim_Manager : elimination_manager_device = elimination_manager_device{}

    # ------------------------------------------------------------------------
    # TUNING CONSTANTS
    # ------------------------------------------------------------------------
    MaxRounds : int = 10          # Total rounds per match.
    RespawnDelay : float = 5.0    # Seconds between rounds (lets respawn finish).
    VoteDuration : float = 15.0   # Loadout vote window.
    WeaponRoomDuration : float = 30.0  # Max time in the weapon room.

    # ------------------------------------------------------------------------
    # STATE (clean, centralized — reset in ResetGame)
    # ------------------------------------------------------------------------
    var LobbyPlayers : []player = array{}            # Players inside Mut_Lobby.
    var WeaponRoomPlayers : []player = array{}       # Players inside Mut_Weapon.
    var PlayerVotes : [player]loadout_type = map{}   # One locked vote per player.
    var RoundWins : [player]int = map{}              # Round wins per player.
    var VotingOpen : logic = false                   # Vote phase active.
    var VotesResolved : logic = false                # ResolveVotes ran (guard).
    var WeaponPhase : logic = false                  # Weapon room phase active.
    var MatchStarted : logic = false                 # RunMatch spawned (guard).
    var MatchInProgress : logic = false              # Rounds currently running.

    # ========================================================================
    # STARTUP — wire every device event.
    # ========================================================================
    OnBegin<override>()<suspends> : void = {
        # Enforce the designed timer durations regardless of editor values.
        Vote_Timer_Device.SetActiveDuration(VoteDuration)
        Weapon_Timer_Device.SetActiveDuration(WeaponRoomDuration)

        # --- Lobby: either the Verse-tracked mutator zone or the linked
        # player counter can start the vote phase (both are guarded).
        Mut_Lobby.AgentEntersEvent.Subscribe(OnLobbyZoneEnter)
        Mut_Lobby.AgentExitsEvent.Subscribe(OnLobbyZoneExit)
        LB_Player_Counter.CountSucceedsEvent.Subscribe(OnLobbyCounterSuccess)

        # --- Voting: walking through a loadout teleporter casts that vote.
        TP_Loadout_Blitz.TeleportedEvent.Subscribe(OnVoteBlitz)
        TP_Loadout_BR.TeleportedEvent.Subscribe(OnVoteBR)
        TP_Loadout_Custom.TeleportedEvent.Subscribe(OnVoteCustom)
        TP_Loadout_Reload.TeleportedEvent.Subscribe(OnVoteReload)
        TP_Loadout_SameLoot.TeleportedEvent.Subscribe(OnVoteSameLoot)
        TP_Loadout_OG.TeleportedEvent.Subscribe(OnVoteOG)

        # --- Vote resolution after 15 seconds.
        Vote_Timer_Device.SuccessEvent.Subscribe(OnVoteTimerEnd)

        # --- Weapon room: 2 players present OR 30s timer starts the match.
        Mut_Weapon.AgentEntersEvent.Subscribe(OnWeaponZoneEnter)
        Mut_Weapon.AgentExitsEvent.Subscribe(OnWeaponZoneExit)
        Weapon_Player_Counter.CountSucceedsEvent.Subscribe(OnWeaponCounterSuccess)
        Weapon_Timer_Device.SuccessEvent.Subscribe(OnWeaponTimerEnd)

        # --- Abort pre-match phases if a player leaves the session.
        GetPlayspace().PlayerRemovedEvent().Subscribe(OnPlayerRemoved)

        Print("Duel Arena Manager initialized. Waiting for 2 players in lobby.")
    }

    # ========================================================================
    # LOBBY SYSTEM
    # ========================================================================
    OnLobbyZoneEnter(Agent : agent) : void = {
        if (Player := player[Agent]) {
            if (not IsInList(Player, LobbyPlayers)) {
                set LobbyPlayers += array{Player}
            }
            if (LobbyPlayers.Length >= 2) {
                BeginVotePhase()
            }
        }
    }

    OnLobbyZoneExit(Agent : agent) : void = {
        if (Player := player[Agent]) {
            set LobbyPlayers = RemoveFromList(Player, LobbyPlayers)
        }
    }

    OnLobbyCounterSuccess() : void = {
        BeginVotePhase()
    }

    # Teleports everyone to the vote room center and opens the 15s vote.
    BeginVotePhase() : void = {
        # Guard: never start voting while another phase is running.
        if (VotingOpen? or WeaponPhase? or MatchStarted?) {
            return
        }
        set LobbyPlayers = array{}
        set PlayerVotes = map{}
        set VotesResolved = false
        ResetVoteBoards()
        for (Player : GetPlayspace().GetPlayers()) {
            TP_LoadoutCenter.Teleport(Player)
        }
        set VotingOpen = true
        Vote_Timer_Device.Start()
        Print("Vote phase started: 15 seconds to choose a loadout.")
    }

    # ========================================================================
    # VOTING SYSTEM
    # ========================================================================
    OnVoteBlitz(Agent : agent) : void = { HandleVote(Agent, loadout_type.Blitz) }
    OnVoteBR(Agent : agent) : void = { HandleVote(Agent, loadout_type.BR) }
    OnVoteCustom(Agent : agent) : void = { HandleVote(Agent, loadout_type.Custom) }
    OnVoteReload(Agent : agent) : void = { HandleVote(Agent, loadout_type.Reload) }
    OnVoteSameLoot(Agent : agent) : void = { HandleVote(Agent, loadout_type.SameLoot) }
    OnVoteOG(Agent : agent) : void = { HandleVote(Agent, loadout_type.OG) }

    # Registers a single locked vote per player, lights the matching switch,
    # increments the matching score manager, and early-resolves once both
    # players have voted.
    HandleVote(Agent : agent, Loadout : loadout_type) : void = {
        if (not VotingOpen?) {
            return
        }
        if (Player := player[Agent]) {
            # Vote locking: ignore any second vote from the same player.
            if (not PlayerVotes[Player]) {
                if (set PlayerVotes[Player] = Loadout) {}
                GetSwitchFor(Loadout).TurnOn(Agent)     # Visual feedback ON.
                GetScoreFor(Loadout).Activate(Agent)    # Vote count +1.
                Print("Vote locked: {LoadoutName(Loadout)}")
                # Both players voted — resolve immediately, no need to wait.
                if (GetVoteCount() >= 2) {
                    Vote_Timer_Device.Reset()
                    ResolveVotes()
                }
            }
        }
    }

    OnVoteTimerEnd(MaybeAgent : ?agent) : void = {
        ResolveVotes()
    }

    # Applies the tie-breaker rules and moves the game forward:
    #   - both voted the same        -> that loadout
    #   - two different votes        -> random between them
    #   - exactly one vote           -> that vote
    #   - no votes                   -> random standard loadout
    #   - Custom ONLY wins when BOTH players voted Custom (rule 8); a lone
    #     Custom vote is dropped from the candidate pool.
    ResolveVotes() : void = {
        if (VotesResolved?) {
            return
        }
        set VotesResolved = true
        set VotingOpen = false

        Votes := for (Key -> Value : PlayerVotes) { Value }
        CustomVotes := for (V : Votes, V = loadout_type.Custom) { V }

        # Rule 8: both players voted Custom -> weapon room path.
        if (CustomVotes.Length >= 2) {
            Print("Both players voted Custom — heading to the weapon room.")
            BeginWeaponRoomPhase()
            return
        }

        # Custom cannot win without both votes, so filter it out.
        Candidates := for (V : Votes, V <> loadout_type.Custom) { V }
        StandardLoadouts : []loadout_type = array{
            loadout_type.Blitz,
            loadout_type.BR,
            loadout_type.Reload,
            loadout_type.SameLoot,
            loadout_type.OG
        }

        var Chosen : loadout_type = loadout_type.BR
        if (Candidates.Length = 0) {
            # No usable votes -> random standard loadout.
            if (RandomPick := StandardLoadouts[GetRandomInt(0, StandardLoadouts.Length - 1)]) {
                set Chosen = RandomPick
            }
        } else if (Candidates.Length = 1) {
            # Single vote -> that vote wins.
            if (OnlyVote := Candidates[0]) {
                set Chosen = OnlyVote
            }
        } else {
            if (VoteA := Candidates[0], VoteB := Candidates[1]) {
                if (VoteA = VoteB) {
                    # Same vote -> selected.
                    set Chosen = VoteA
                } else {
                    # Different votes -> coin flip between the two.
                    if (GetRandomInt(0, 1) = 0) {
                        set Chosen = VoteA
                    } else {
                        set Chosen = VoteB
                    }
                }
            }
        }

        Print("Loadout selected: {LoadoutName(Chosen)}")
        ApplyLoadout(Chosen)
        StartMatch()
    }

    # Number of locked votes so far.
    GetVoteCount() : int = {
        VoteList := for (Key -> Value : PlayerVotes) { Value }
        VoteList.Length
    }

    # Grants the winning loadout to every player. Items persist across rounds
    # ("Keep Items on Respawn" island setting) so this runs only once.
    ApplyLoadout(Loadout : loadout_type) : void = {
        for (Player : GetPlayspace().GetPlayers()) {
            if (Loadout = loadout_type.Blitz) {
                IG_Blitz.GrantItem(Player)
            } else if (Loadout = loadout_type.Reload) {
                IG_Reload.GrantItem(Player)
            } else if (Loadout = loadout_type.SameLoot) {
                IG_Sameloot.GrantItem(Player)
            } else if (Loadout = loadout_type.OG) {
                IG_OG.GrantItem(Player)
            }
            # BR: no granter by design — players fight over map loot.
        }
    }

    # ========================================================================
    # WEAPON ROOM SYSTEM (Custom loadout)
    # ========================================================================
    BeginWeaponRoomPhase() : void = {
        set WeaponPhase = true
        set WeaponRoomPlayers = array{}
        for (Player : GetPlayspace().GetPlayers()) {
            TP_WeaponRoom.Teleport(Player)
        }
        Weapon_Timer_Device.Start()
        Print("Weapon room open: grab weapons. Match starts when both players stand in the zone or in 30 seconds.")
    }

    OnWeaponZoneEnter(Agent : agent) : void = {
        if (Player := player[Agent]) {
            if (not IsInList(Player, WeaponRoomPlayers)) {
                set WeaponRoomPlayers += array{Player}
            }
            # Verse-side detection: both players standing in Mut_Weapon.
            if (WeaponPhase? and WeaponRoomPlayers.Length >= 2) {
                StartMatchFromWeaponRoom()
            }
        }
    }

    OnWeaponZoneExit(Agent : agent) : void = {
        if (Player := player[Agent]) {
            set WeaponRoomPlayers = RemoveFromList(Player, WeaponRoomPlayers)
        }
    }

    # Device-side detection: Weapon_Player_Counter hit its target of 2.
    OnWeaponCounterSuccess() : void = {
        if (WeaponPhase?) {
            StartMatchFromWeaponRoom()
        }
    }

    # Timer fallback: 30 seconds elapsed in the weapon room.
    OnWeaponTimerEnd(MaybeAgent : ?agent) : void = {
        if (WeaponPhase?) {
            StartMatchFromWeaponRoom()
        }
    }

    StartMatchFromWeaponRoom() : void = {
        set WeaponPhase = false
        Weapon_Timer_Device.Reset()
        StartMatch()
    }

    # ========================================================================
    # MATCH SYSTEM — 10 rounds, 3 random zones
    # ========================================================================
    StartMatch() : void = {
        if (not MatchStarted?) {
            set MatchStarted = true
            spawn { RunMatch() }
        }
    }

    RunMatch()<suspends> : void = {
        Players := GetPlayspace().GetPlayers()
        if (Players.Length < 2) {
            Print("Match aborted: fewer than 2 players.")
            ResetGame()
            return
        }
        if (Player1 := Players[0], Player2 := Players[1]) {
            set MatchInProgress = true
            set RoundWins = map{}
            Print("Match starting: {MaxRounds} rounds.")

            var RoundNumber : int = 1
            loop {
                if (RoundNumber > MaxRounds) {
                    break
                }
                # 3-zone random round system: pick zone 0..2 each round.
                ZoneIndex := GetRandomInt(0, 2)
                Winner := StartRound(Player1, Player2, ZoneIndex, RoundNumber)
                EndRound(Winner, RoundNumber)
                # Stop early if someone left the session mid-match.
                if (not IsInPlayspace(Player1) or not IsInPlayspace(Player2)) {
                    Print("Match ended early: a player left the session.")
                    break
                }
                set RoundNumber += 1
            }

            AnnounceMatchWinner(Player1, Player2)
        }
        ResetGame()
    }

    # Teleports both players into the chosen zone, raises that zone's storm,
    # and waits for a real elimination to decide the round winner.
    StartRound(Player1 : player, Player2 : player, ZoneIndex : int, RoundNumber : int)<suspends> : player = {
        Print("Round {RoundNumber} — fighting in Zone {ZoneIndex + 1}.")
        TeleportToSpawn(Player1, GetZoneSpawn(ZoneIndex, 1))
        TeleportToSpawn(Player2, GetZoneSpawn(ZoneIndex, 2))

        # Storm system per zone: only the matching controller activates.
        Storm := GetZoneStorm(ZoneIndex)
        Storm.GenerateStorm()

        # Real elimination detection: whichever fires first ends the round.
        # Third racer handles a player disconnecting mid-round.
        Winner := race {
            AwaitElimination(Player1, Player2)
            AwaitElimination(Player2, Player1)
            AwaitPlayerLeaving(Player1, Player2)
        }

        Storm.DestroyStorm()
        Winner
    }

    # Resolves when Victim's fort_character is eliminated; returns the winner.
    # If Victim has no valid character (left / not spawned) the opponent wins
    # the round immediately.
    AwaitElimination(Victim : player, Opponent : player)<suspends> : player = {
        if (VictimCharacter := Victim.GetFortCharacter[]) {
            VictimCharacter.EliminatedEvent().Await()
            return Opponent
        }
        Opponent
    }

    # Resolves only if one of the two duelists leaves the session mid-round.
    AwaitPlayerLeaving(Player1 : player, Player2 : player)<suspends> : player = {
        loop {
            Removed := GetPlayspace().PlayerRemovedEvent().Await()
            if (Removed = Player1) {
                return Player2
            }
            if (Removed = Player2) {
                return Player1
            }
        }
    }

    # Records the round win and gives the eliminated player time to respawn
    # (island respawn sends them to the lobby spawners; the next round
    # teleports both players into the new zone).
    EndRound(Winner : player, RoundNumber : int)<suspends> : void = {
        CurrentWins := GetWins(Winner)
        if (set RoundWins[Winner] = CurrentWins + 1) {}
        Print("Round {RoundNumber} over. Winner now has {CurrentWins + 1} round win(s).")
        Sleep(RespawnDelay)
    }

    GetWins(Player : player) : int = {
        if (Wins := RoundWins[Player]) {
            Wins
        } else {
            0
        }
    }

    AnnounceMatchWinner(Player1 : player, Player2 : player) : void = {
        Wins1 := GetWins(Player1)
        Wins2 := GetWins(Player2)
        if (Wins1 > Wins2) {
            Print("MATCH OVER — Player 1 wins {Wins1} to {Wins2}!")
        } else if (Wins2 > Wins1) {
            Print("MATCH OVER — Player 2 wins {Wins2} to {Wins1}!")
        } else {
            Print("MATCH OVER — Draw at {Wins1} round(s) each!")
        }
    }

    # ========================================================================
    # RESET SYSTEM — returns everything to a clean lobby state.
    # ========================================================================
    ResetGame() : void = {
        # Flags.
        set MatchInProgress = false
        set MatchStarted = false
        set VotingOpen = false
        set VotesResolved = false
        set WeaponPhase = false
        # Collections.
        set PlayerVotes = map{}
        set RoundWins = map{}
        set LobbyPlayers = array{}
        set WeaponRoomPlayers = array{}
        # Devices.
        Vote_Timer_Device.Reset()
        Weapon_Timer_Device.Reset()
        Storm_Zone1.DestroyStorm()
        Storm_Zone2.DestroyStorm()
        Storm_Zone3.DestroyStorm()
        ResetVoteBoards()
        # Send everyone back to the lobby; walking back into Mut_Lobby with
        # 2 players starts the next match cycle automatically.
        for (Player : GetPlayspace().GetPlayers()) {
            TP_Lobby.Teleport(Player)
        }
        Print("Game reset. Back to lobby — next match starts when 2 players are ready.")
    }

    # Turns every vote switch off and zeroes every vote score manager.
    ResetVoteBoards() : void = {
        for (Player : GetPlayspace().GetPlayers()) {
            Switch_Blitz.TurnOff(Player)
            Switch_BR.TurnOff(Player)
            Switch_Custom.TurnOff(Player)
            Switch_Reload.TurnOff(Player)
            Switch_Sameloot.TurnOff(Player)
            Switch_OG.TurnOff(Player)
            Score_Blitz.Reset(Player)
            Score_BR.Reset(Player)
            Score_Custom.Reset(Player)
            Score_Reload.Reset(Player)
            Score_Sameloot.Reset(Player)
            Score_OG.Reset(Player)
        }
    }

    # ========================================================================
    # SESSION EVENTS
    # ========================================================================
    OnPlayerRemoved(Player : player) : void = {
        set LobbyPlayers = RemoveFromList(Player, LobbyPlayers)
        set WeaponRoomPlayers = RemoveFromList(Player, WeaponRoomPlayers)
        # Mid-match departures are handled inside the round race; only the
        # pre-match phases need an explicit abort here.
        if (VotingOpen? or WeaponPhase?) {
            Print("A player left before the match started — resetting.")
            ResetGame()
        }
    }

    # ========================================================================
    # HELPERS
    # ========================================================================
    # Moves a player onto a zone spawn pad using its world transform.
    TeleportToSpawn(Player : player, Spawn : player_spawner_device) : void = {
        if (Character := Player.GetFortCharacter[]) {
            SpawnTransform := Spawn.GetTransform()
            if (Character.TeleportTo[SpawnTransform.Translation, SpawnTransform.Rotation]) {}
        }
    }

    # Zone lookup tables (ZoneIndex 0..2, PlayerSlot 1..2).
    GetZoneSpawn(ZoneIndex : int, PlayerSlot : int) : player_spawner_device = {
        if (ZoneIndex = 0) {
            if (PlayerSlot = 1) { ZONE1_T1Spawn } else { ZONE1_T2Spawn }
        } else if (ZoneIndex = 1) {
            if (PlayerSlot = 1) { ZONE2_T1Spawn } else { ZONE2_T2Spawn }
        } else {
            if (PlayerSlot = 1) { ZONE3_T1Spawn } else { ZONE3_T2Spawn }
        }
    }

    GetZoneStorm(ZoneIndex : int) : basic_storm_controller_device = {
        if (ZoneIndex = 0) {
            Storm_Zone1
        } else if (ZoneIndex = 1) {
            Storm_Zone2
        } else {
            Storm_Zone3
        }
    }

    GetSwitchFor(Loadout : loadout_type) : switch_device = {
        if (Loadout = loadout_type.Blitz) {
            Switch_Blitz
        } else if (Loadout = loadout_type.BR) {
            Switch_BR
        } else if (Loadout = loadout_type.Custom) {
            Switch_Custom
        } else if (Loadout = loadout_type.Reload) {
            Switch_Reload
        } else if (Loadout = loadout_type.SameLoot) {
            Switch_Sameloot
        } else {
            Switch_OG
        }
    }

    GetScoreFor(Loadout : loadout_type) : score_manager_device = {
        if (Loadout = loadout_type.Blitz) {
            Score_Blitz
        } else if (Loadout = loadout_type.BR) {
            Score_BR
        } else if (Loadout = loadout_type.Custom) {
            Score_Custom
        } else if (Loadout = loadout_type.Reload) {
            Score_Reload
        } else if (Loadout = loadout_type.SameLoot) {
            Score_Sameloot
        } else {
            Score_OG
        }
    }

    LoadoutName(Loadout : loadout_type) : string = {
        if (Loadout = loadout_type.Blitz) {
            "Blitz"
        } else if (Loadout = loadout_type.BR) {
            "BR"
        } else if (Loadout = loadout_type.Custom) {
            "Custom"
        } else if (Loadout = loadout_type.Reload) {
            "Reload"
        } else if (Loadout = loadout_type.SameLoot) {
            "Same Loot"
        } else {
            "OG"
        }
    }

    IsInList(Player : player, List : []player) : logic = {
        for (Other : List) {
            if (Other = Player) {
                return true
            }
        }
        false
    }

    RemoveFromList(Player : player, List : []player) : []player = {
        for (Other : List, Other <> Player) { Other }
    }

    IsInPlayspace(Player : player) : logic = {
        IsInList(Player, GetPlayspace().GetPlayers())
    }
}
