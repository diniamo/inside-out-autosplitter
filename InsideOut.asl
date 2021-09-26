// Watcher logic + settings

state("InsideOut")
{
	int sceneIndex : "UnityPlayer.dll", 0x18148E8, 0x48, 0x98;
}

startup
{
	vars.Dbg = (Action<dynamic>) ((output) => print("[Inside | Out ASL] " + output));


	settings.Add("seasons", false, "Season Splits");

	settings.Add("dry", false, "Split on dry season change", "seasons");
	settings.Add("green", false, "Split on green season change", "seasons");
}

init
{
	var CLASSES = new Dictionary<string, IntPtr>
	{
		{ "GameManager", IntPtr.Zero },
		{ "PauseMenu", IntPtr.Zero },
		{ "FPSController", IntPtr.Zero }
	};

	vars.CancelSource = new CancellationTokenSource();
	vars.ScanThread = new Thread(() =>
	{
		vars.Dbg("Starting scan thread.");

		ProcessModuleWow64Safe gameAssembly = null;
		IntPtr classSequence = IntPtr.Zero;

		var classSequenceTrg = new SigScanTarget(3, "48 8B 05 ???????? 48 83 3C ?? 00 75 ?? 48 8D 35")
		{ OnFound = (p, s, ptr) => p.ReadPointer(ptr + 0x4 + p.ReadValue<int>(ptr)) + 0x18 };

		var token = vars.CancelSource.Token;
		while (!token.IsCancellationRequested)
		{
			gameAssembly = game.ModulesWow64Safe().FirstOrDefault(m => m.ModuleName == "GameAssembly.dll");

			if (gameAssembly != null)
				break;

			vars.Dbg("GameAssembly module not found.");
			Thread.Sleep(2000);
		}

		while (!token.IsCancellationRequested)
		{
			var gaScanner = new SignatureScanner(game, gameAssembly.BaseAddress, gameAssembly.ModuleMemorySize);

			if ((classSequence = gaScanner.Scan(classSequenceTrg)) != IntPtr.Zero)
			{
				vars.Dbg("Found 'ClassSequence' at 0x" + classSequence.ToString("X"));
				break;
			}

			vars.Dbg("'ClassSequence' not found.");
			Thread.Sleep(2000);
		}

		while (!token.IsCancellationRequested)
		{
			bool allFound = false;
			IntPtr klass = game.ReadPointer(classSequence);

			for (int i = 0; klass != IntPtr.Zero; i += 0x8, klass = game.ReadPointer(classSequence + i))
			{
				string name = new DeepPointer(klass + 0x10, 0x0).DerefString(game, 64);
				if (!CLASSES.Keys.Contains(name)) continue;

				CLASSES[name] = game.ReadPointer(klass + 0xB8);
				vars.Dbg("Found '" + name + "' at 0x" + CLASSES[name].ToString("X") + ".");

				if (allFound = CLASSES.Values.All(ptr => ptr != IntPtr.Zero))
					break;
			}

			if (allFound)
			{
				vars.Watchers = new MemoryWatcherList
				{
					new MemoryWatcher<bool>(new DeepPointer(CLASSES["GameManager"], 0x18)) { Name = "isDrySeason" },
                    new MemoryWatcher<bool>(new DeepPointer(CLASSES["GameManager"], 0x19)) { Name = "isGreenSeason" },
                    //new MemoryWatcher<bool>(new DeepPointer(CLASSES["GameManager"], 0x1a)) { Name = "isSnowSeason" },

                    new MemoryWatcher<bool>(new DeepPointer(CLASSES["FPSController"], 0x18)) { Name = "canMove" },
                    new MemoryWatcher<bool>(new DeepPointer(CLASSES["PauseMenu"], 0x19)) { Name = "canPause" }
				};

				vars.Dbg("All classes found.");
				break;
			}

			vars.Dbg("Not all classes found yet.");
			Thread.Sleep(5000);
		}

		vars.Dbg("Exiting scan thread.");
	});

	vars.ScanThread.Start();
}

update
{
	if (vars.ScanThread.IsAlive) return false;

	vars.Watchers.UpdateAll(game);
}

exit
{
	vars.CancelSource.Cancel();
}

shutdown
{
	vars.CancelSource.Cancel();
}

// Splitting logic
// vars.Watchers["bool1"].Current, vars.Watchers["bool1"].Old, vars.Watchers["bool1"].Changed

start
{
	var canMove = vars.Watchers["canMove"];

	return canMove.Old == false && canMove.Current == true;
}

split
{
	if(settings["seasons"])
	{
		return (settings["dry"] && vars.Watchers["isDrySeason"].Changed) || (settings["green"] && vars.Watchers["isGreenSeason"].Changed)
			|| vars.Watchers["canPause"].Changed;
	} else
	{
		return vars.Watchers["canPause"].Changed;
	}
}

reset
{
	return old.sceneIndex == 1 && current.sceneIndex == 0;
}