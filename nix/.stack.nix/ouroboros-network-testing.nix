{ system
  , compiler
  , flags
  , pkgs
  , hsPkgs
  , pkgconfPkgs
  , errorHandler
  , config
  , ... }:
  {
    flags = {};
    package = {
      specVersion = "1.10";
      identifier = { name = "ouroboros-network-testing"; version = "0.1.0.0"; };
      license = "Apache-2.0";
      copyright = "2019 Input Output (Hong Kong) Ltd.";
      maintainer = "";
      author = "Alexander Vieth, Marcin Szamotulski, Duncan Coutts, Karl Knuttson";
      homepage = "";
      url = "";
      synopsis = "Common modules used for testing in ouroboros-network and ouroboros-consensus";
      description = "";
      buildType = "Simple";
      isLocal = true;
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."base" or (errorHandler.buildDepError "base"))
          (hsPkgs."io-sim" or (errorHandler.buildDepError "io-sim"))
          (hsPkgs."cborg" or (errorHandler.buildDepError "cborg"))
          (hsPkgs."serialise" or (errorHandler.buildDepError "serialise"))
          (hsPkgs."QuickCheck" or (errorHandler.buildDepError "QuickCheck"))
          ];
        buildable = true;
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "https://github.com/input-output-hk/ouroboros-network";
      rev = "aecfe77de784e6c75108172802ee59d2d7087eaf";
      sha256 = "1pdanljh5v1w038fc0s945h1gnrkipnfbj2cqqzwgpnv7zm14swh";
      });
    postUnpack = "sourceRoot+=/ouroboros-network-testing; echo source root reset to \$sourceRoot";
    }