state("TimothyVsTheAliens-Win64-Shipping"){}

startup
{
    vars.Log = (Action<object>)((output) => print("[TVTA ASL] " + output));
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

    vars.UWorld = vars.GetStaticPointerFromSig("48 89 05 ?? ?? ?? ?? 49 8B B4 24", 0x3);

    if(vars.UWorld == IntPtr.Zero)
    {
        throw new Exception("UWorld not initialized - trying again");
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
        new MemoryWatcher<int>(new DeepPointer(vars.UWorld, 0x180, 0x1B1)) { Name = "NewGame" },
    };

    vars.isLoading = false;
}

update
{
    vars.watchers.UpdateAll(game);
    current.inGame = vars.watchers["InGameGameMode"].Current != 0;
    current.loadingHud = vars.watchers["Loading"].Current != 0;
    current.unloadingHud = vars.watchers["Unloading"].Current != 0;
    current.mainMenuHud = vars.watchers["MainMenu"].Current != 0;
    current.logoHud = vars.watchers["Logo"].Current != 0;
    current.newGame = vars.watchers["NewGame"].Current != 0;
}

start 
{
    return current.newGame;
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