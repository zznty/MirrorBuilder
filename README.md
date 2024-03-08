# MirrorBuilder

MirrorBuilder is a repository containing scripts and CI pipelines for building Minecraft clients from MultiMC compatible metadata. Additionally, it includes important tweaks to ensure compatibility with the GraivtLauncher project.

## Local Build Instructions

To build the Minecraft client locally using MirrorBuilder, follow these steps:

### Prerequisites

1. Install the latest version of PowerShell:
   - For Windows, follow the instructions [here](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).
   - For Linux, follow the instructions [here](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux).

2. Install JDK 17:
   - You can install JDK 17 using `winget` for Windows:
     ```
     winget install --id EclipseAdoptium.Temurin.17.JDK --source winget
     ```
   - For Linux, use your package manager to install JDK 17.

3. For 1.18.x Forge clients, JDK 16 is also required:
   - Install JDK 16 using `winget` for Windows:
     ```
     winget install --id EclipseAdoptium.Temurin.16.JDK --source winget
     ```
   - For Linux, use your package manager to install JDK 16.

### Setting up Dependencies

4. Launch PowerShell using the `pwsh` command.

5. Install PSCompression, a required dependency:
   ```powershell
   Set-PSRepository PSGallery -InstallationPolicy Trusted
   Install-Module PSCompression
   ```

6. Create the desired directory and switch to it. For example:
   ```powershell
   mkdir MinecraftBuild
   cd MinecraftBuild
   ```

### Building the Client

7. Execute the script:
   ```powershell
   ../installComponent.ps1 <component uid> <component version>
   ```

   Replace `<component uid>` with either `net.minecraftforge` or `net.fabricmc.intermediary`. For Forge clients, use the version from the official website. For Fabric clients, use the desired Minecraft version (release or snapshot).

8. For Fabric clients, install Fabric Loader using the same script, but with `net.fabricmc.fabric-loader` as the component uid and the latest Fabric Loader version.

### Final Steps

9. Copy the contents of the directory to the `updates/<your client name>` folder in the launch server.

10. Move `profile.json` to `profiles/<your client name>.json`.

## Compatibility

MirrorBuilder scripts can be run on both Windows and Linux operating systems.

For any further assistance or issues, please refer to the repository or contact the maintainers.