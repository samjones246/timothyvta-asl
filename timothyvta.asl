state("TimothyVsTheAliens-Win64-Shipping"){}

startup
{
    vars.Log = (Action<object>)((output) => print("[TVTA ASL] " + output));
    vars.SEWERS_LEVEL_NAME = "CitySewer_StreamLevel";
    vars.CITY_LEVEL_NAME = "LittleFishCity_StreamLevel";
    vars.CAFE_LEVEL_NAME = "ElizabethRest_StreamLevel";

    settings.Add("split_tnt", true, "Split on TNT collected");
    settings.Add("split_tnt_1", true, "Construction Site", "split_tnt");
    settings.Add("split_tnt_2", true, "Port", "split_tnt");
    settings.Add("split_tnt_3", true, "Graveyard", "split_tnt");

    settings.Add("split_sewers", true, "Split on first sewers entry");
    settings.Add("split_cafe", true, "Split on leaving cafe");
    settings.Add("split_wall", true, "Split on destroying wall");
    settings.Add("split_boss", true, "Split on defeating final boss");
}

init
{
    vars.GetStaticPointerFromSig = (Func<string, int, IntPtr>) ( (signature, instructionOffset) => {
        var scanner = new SignatureScanner(game, modules.First().BaseAddress, (int)modules.First().ModuleMemorySize);
        var pattern = new SigScanTarget(signature);
        var location = scanner.Scan(pattern);
        if (location == IntPtr.Zero) return IntPtr.Zero;
        int offset = game.ReadValue<int>((IntPtr)location + instructionOffset);
        var ptr = (IntPtr)location + offset + instructionOffset + 0x4;
        vars.Log("Found pointer from sig: " + ptr.ToString("X"));
        return ptr;
    });

     vars.GetNameFromFName = (Func<long, string>) ( longKey => {
        int key = (int)(longKey & uint.MaxValue);
        int partial = (int)(longKey >> 32);
        int chunkOffset = key >> 16;
        int nameOffset = (ushort)key;
        IntPtr namePoolChunk = memory.ReadValue<IntPtr>((IntPtr)vars.FNamePool + (chunkOffset+2) * 0x8);
        Int16 nameEntry = game.ReadValue<Int16>((IntPtr)namePoolChunk + 2 * nameOffset);
        int nameLength = nameEntry >> 6;
        string output = game.ReadString((IntPtr)namePoolChunk + 2 * nameOffset + 2, nameLength);
        return (partial == 0) ? output : output + "_" + partial.ToString();
    });
    
    vars.FNamePool = vars.GetStaticPointerFromSig("74 09 48 8D 15 ?? ?? ?? ?? EB 16", 0x5);
    vars.UWorld = vars.GetStaticPointerFromSig("48 89 05 ?? ?? ?? ?? 49 8B B4 24", 0x3);

    if(vars.UWorld == IntPtr.Zero || vars.FNamePool == IntPtr.Zero)
    {
        throw new Exception("UWorld/FNamePool not initialized - trying again");
    }

    vars.watchers = new MemoryWatcherList
    {
        // UWorld.OwningGameInstance.InGameGameMode
        new MemoryWatcher<long>(new DeepPointer(vars.UWorld, 0x180, 0x218)) { Name = "InGameGameMode" },

        // UWorld.OwningGameInstance.InGameGameMode.LoadingHUD.ActiveSequencePlayers
        new MemoryWatcher<long>(new DeepPointer(vars.UWorld, 0x180, 0x218, 0x2E8, 0x1A0)) { Name = "Loading" },
        
        // UWorld.OwningGameInstance.InGameGameMode.UnloadingHUD.ActiveSequencePlayers
        new MemoryWatcher<long>(new DeepPointer(vars.UWorld, 0x180, 0x218, 0x390, 0x1A0)) { Name = "Unloading" },

        // UWorld.OwningGameInstance.MainMenuHUD.ActiveSequencePlayers
        new MemoryWatcher<long>(new DeepPointer(vars.UWorld, 0x180, 0x210, 0x1A0)) { Name = "MainMenu" },

        // ???.LogoScreen.ActiveSequencePlayers (sorry)
        new MemoryWatcher<long>(new DeepPointer(vars.UWorld, 0x30, 0x98, 0x10, 0x220, 0x20, 0x1A0)) { Name = "Logo" },

        // UWorld.OwningGameInstance.NewGame
        new MemoryWatcher<bool>(new DeepPointer(vars.UWorld, 0x180, 0x1B1)) { Name = "NewGame" },

        // UWorld.OwningGameInstance.InGameGameMode.LoadingHUD.LevelToLoadName
        new MemoryWatcher<int>(new DeepPointer(vars.UWorld, 0x180, 0x218, 0x2E8, 0x260)) { Name = "LevelToLoadName" },

        // UWorld.OwningGameInstance.InGameGameMode.GameDetailsSaveGame.TNT_1
        new MemoryWatcher<bool>(new DeepPointer(vars.UWorld, 0x180, 0x218, 0x2F0, 0x0DD)) { Name = "TNT_1" },

        // UWorld.OwningGameInstance.InGameGameMode.GameDetailsSaveGame.TNT_2
        new MemoryWatcher<bool>(new DeepPointer(vars.UWorld, 0x180, 0x218, 0x2F0, 0x0DE)) { Name = "TNT_2" },

        // UWorld.OwningGameInstance.InGameGameMode.GameDetailsSaveGame.TNT_3
        new MemoryWatcher<bool>(new DeepPointer(vars.UWorld, 0x180, 0x218, 0x2F0, 0x0DF)) { Name = "TNT_3" },

        // UWorld.OwningGameInstance.InGameGameMode.GameDetailsSaveGame.WallExpoted (their typo not mine)
        new MemoryWatcher<bool>(new DeepPointer(vars.UWorld, 0x180, 0x218, 0x2F0, 0x0E0)) { Name = "WallExploded" },
    };

    vars.isLoading = false;
    vars.triggeredSplits = new Dictionary<string, bool>() {
        { "split_tnt_1", false },
        { "split_tnt_2", false },
        { "split_tnt_3", false },
        { "split_sewers", false },
        { "split_cafe", false },
        { "split_wall", false },
        { "split_boss", false },
    };

    vars.shouldSplit = (Func<string, bool>)((splitName) =>
        settings[splitName] && !vars.triggeredSplits[splitName]
    );
    old.levelToLoad = "";
}

update
{
    vars.watchers.UpdateAll(game);
    current.inGame = vars.watchers["InGameGameMode"].Current != 0;
    current.loadingHud = vars.watchers["Loading"].Current != 0;
    current.unloadingHud = vars.watchers["Unloading"].Current != 0;
    current.mainMenuHud = vars.watchers["MainMenu"].Current != 0;
    current.logoHud = vars.watchers["Logo"].Current != 0;
    current.newGame = vars.watchers["NewGame"].Current;
    current.levelToLoad = vars.GetNameFromFName(vars.watchers["LevelToLoadName"].Current);
    current.hasConstructionTnt = vars.watchers["TNT_1"].Current;
    current.hasPortTnt = vars.watchers["TNT_2"].Current;
    current.hasGraveyardTnt = vars.watchers["TNT_3"].Current;
    current.wallExploded = vars.watchers["WallExploded"].Current;

    if (current.levelToLoad != old.levelToLoad) {
        vars.Log("Loading: " + current.levelToLoad);
    }
}

start 
{
    return current.newGame && !old.newGame;
}

split
{
    if (current.hasConstructionTnt && !old.hasConstructionTnt && vars.shouldSplit("split_tnt_1")) {
        vars.shouldSplit("split_tnt_1") = true;
        return true;
    }
    if (current.hasPortTnt && !old.hasPortTnt && vars.shouldSplit("split_tnt_2")) {
        vars.shouldSplit("split_tnt_2") = true;
        return true;
    }
    if (current.hasGraveyardTnt && !old.hasGraveyardTnt && vars.shouldSplit("split_tnt_3")) {
        vars.shouldSplit("split_tnt_3") = true;
        return true;
    }

    if (current.levelToLoad != old.levelToLoad) {
        if (current.levelToLoad == vars.SEWERS_LEVEL_NAME && vars.shouldSplit("split_sewers")) {
            vars.shouldSplit("split_sewers") = true;
            return true;
        }
        if (old.levelToLoad == vars.CAFE_LEVEL_NAME && vars.shouldSplit("split_cafe")) {
            vars.shouldSplit("split_cafe") = true;
            return true;
        }
    }

    if (current.wallExploded && !old.wallExploded && vars.shouldSplit("split_wall")) {
        vars.shouldSplit("split_wall") = true;
        return true;
    }
}

isLoading
{
    if (current.inGame) {
        if (current.unloadingHud) {
            vars.isLoading = true;
        }
        if (old.loadingHud && !current.loadingHud) {
            vars.isLoading = false;
        }
    } else {
        // Menu load 1 start
        if (old.logoHud && !current.logoHud) {
            vars.isLoading = true;
        }
        // Menu load 1 end
        if (current.mainMenuHud && !old.mainMenuHud) {
            vars.isLoading = false;
        }
        // Menu load 2 start
        if (old.mainMenuHud && !current.mainMenuHud) {
            vars.isLoading = true;
        }
    }
    return vars.isLoading;
}