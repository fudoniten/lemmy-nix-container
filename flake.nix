{
  description = "Lemmy running in a container";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.11";
    arion.url = "github:hercules-ci/arion";
  };

  outputs = { self, nixpkgs, arion, ... }: {
    nixosModules = rec {
      default = lemmyContainer;
      lemmyContainer = { ... }: {
        imports = [ arion.nixosModules.arion ./lemmy-container.nix ];
      };
    };
  };
}
