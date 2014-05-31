{stdenv, dotnetfx}:
{ name
, src
, baseDir ? "."
, slnFile
, targets ? "ReBuild"
, verbosity ? "detailed"
, options ? ""
, assemblyInputs ? []
, preBuild ? ""
, modifyPublicMain ? false
, mainClassFile ? null
, preInstall ? ""
, postInstall ? ""
}:

assert modifyPublicMain -> mainClassFile != null;

let
  wrapperCS = ./Wrapper.cs.in;
in
stdenv.mkDerivation {
  inherit name src;
  
  buildInputs = [ dotnetfx ];
  
  # The system drive must be set so that Visual C++ builds don't fail with an error message saying that a path is not well formed
  SYSTEMDRIVE = "C:";

  preConfigure = ''
    cd ${baseDir}
  '';
  
  preBuild = ''
    ${stdenv.lib.optionalString modifyPublicMain ''
      sed -i -e "s|static void Main|public static void Main|" ${mainClassFile}
    ''}
    
    ${preBuild}
  '';
  
  installPhase = ''
    ${preInstall}
    
    addAssemblyDeps()
    {
        if [ -f $1/nix-support/dotnet-assemblies ]
        then
            for i in $(cat $1/nix-support/dotnet-assemblies)
            do
                windowsPath=$(cygpath --windows $i)
                assemblySearchPaths="$assemblySearchPaths;$windowsPath"
                
                addAssemblyDeps $i
            done
        fi
    }
    
    for i in ${toString assemblyInputs}
    do
        windowsPath=$(cygpath --windows $i) 
        echo "Using assembly path: $windowsPath"
        
        if [ "$assemblySearchPaths" = "" ]
        then
            assemblySearchPaths="$windowsPath"
        else
            assemblySearchPaths="$assemblySearchPaths;$windowsPath"
        fi
        
        addAssemblyDeps $i
    done
      
    echo "Assembly search paths are: $assemblySearchPaths"
    
    if [ "$assemblySearchPaths" != "" ]
    then
        echo "Using assembly search paths args: $assemblySearchPathsArg"
        export AssemblySearchPaths=$assemblySearchPaths
    fi
    
    mkdir -p $out
    export AdditionalIncludeDirectories="$AssemblySearchPaths"
    
    MSBuild.exe /nologo /t:${targets} /p:IntermediateOutputPath=$(cygpath --windows $out)'\' /p:OutDir=$(cygpath --windows $out)'\' /p:OutputPath=$(cygpath --windows $out)'\' /verbosity:${verbosity} ${options} $msBuildOpts ${toString slnFile} 
    
    # Because .NET assemblies store strings as UTF-16 internally, we cannot detect
    # hashes. Therefore a text files containing the proper paths is created
    # We can also use this file the propagate transitive dependencies.
    
    mkdir -p $out/nix-support
    
    for i in ${toString assemblyInputs}
    do
        echo $i >> $out/nix-support/dotnet-assemblies
    done
    
    ${postInstall}
  '';
}
