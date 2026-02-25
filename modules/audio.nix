# PipeWire low-latency audio — important for VR and gaming
{ ... }: {
  # Disable PulseAudio — PipeWire replaces it entirely
  services.pulseaudio.enable = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;  # Required for 32-bit game audio (Proton/Wine)
    pulse.enable = true;       # PulseAudio compatibility layer
    jack.enable = true;        # JACK compatibility — used by some pro audio/VR apps
    wireplumber.enable = true; # Session/policy manager for PipeWire
  };

  # Fix Valve Index audio dropout under GPU load.
  # The Index HMD presents as a USB audio device whose ALSA node name contains "Valve".
  # Increasing period-size and headroom trades ~20ms latency for dropout-free audio.
  services.pipewire.wireplumber.extraConfig."99-valve-index" = {
    "monitor.alsa.rules" = [{
      matches = [{ "node.name" = "~alsa_output.*[Vv]alve.*"; }];
      actions.update-props = {
        "api.alsa.period-size" = 1024;
        "api.alsa.headroom"    = 8192;
      };
    }];
  };

  # Realtime scheduling for audio threads — reduces audio dropouts in VR
  security.rtkit.enable = true;
}
