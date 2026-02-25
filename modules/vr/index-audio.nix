# Valve Index audio switching — automatically routes audio to/from
# the Index headset when VR starts/stops.
#
# Requires user to configure device names discovered via:
#   pactl list cards
#   pactl list short sinks
#   pactl list short sources
#
# Set the options in hosts/gaming/default.nix:
#   myOS.vr.audio = {
#     enable = true;
#     card = "alsa_card.usb-Valve_Corporation_Valve_VR_Radio___HMD_Mic-01";
#     profile = "output:iec958-stereo+input:mono-fallback";
#     source = "alsa_input.usb-Valve_Corporation_Valve_VR_Radio___HMD_Mic-01.mono-fallback";
#     sink = "alsa_output.usb-Valve_Corporation_Valve_VR_Radio___HMD_Mic-01.iec958-stereo";
#     defaultSource = "your-normal-mic-source";
#     defaultSink = "your-normal-speakers-sink";
#   };
{ config, lib, pkgs, ... }:
let
  cfg = config.myOS.vr;
  audioCfg = cfg.audio;
in
lib.mkIf (cfg.enable && audioCfg.enable) {
  systemd.user.services.valve-index-audio = {
    description = "Valve Index Audio Switching";
    # Bind to monado so audio switches automatically with VR start/stop
    bindsTo = lib.mkIf (cfg.runtime == "monado") [ "monado.service" ];
    after = lib.mkIf (cfg.runtime == "monado") [ "monado.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      ExecStart = pkgs.writeShellScript "index-audio-start" ''
        # Set the Index card profile
        ${pkgs.pulseaudio}/bin/pactl set-card-profile "${audioCfg.card}" "${audioCfg.profile}"

        # Set Index as default source (microphone) immediately
        ${pkgs.pulseaudio}/bin/pactl set-default-source "${audioCfg.source}"

        # The Index audio sink needs time to power on after the HMD activates.
        # Setting it too early results in no audio output.
        sleep 10

        # Set Index as default sink (speakers/headphones)
        ${pkgs.pulseaudio}/bin/pactl set-default-sink "${audioCfg.sink}"
      '';

      ExecStop = pkgs.writeShellScript "index-audio-stop" ''
        # Restore normal audio devices
        ${pkgs.pulseaudio}/bin/pactl set-default-source "${audioCfg.defaultSource}"
        ${pkgs.pulseaudio}/bin/pactl set-default-sink "${audioCfg.defaultSink}"
      '';
    };
  };
}
