"""Copies the throwaway probe addon (tools/probe/AzGF_Probe) into the WoW AddOns folder.

The folder is read from tools/local.ini (git-ignored); see tools/local.example.ini.
Usage: python -I -X utf8 tools/install_probe.py
"""
import configparser
import os
import shutil
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(TOOLS, "probe", "AzGF_Probe")
INI = os.path.join(TOOLS, "local.ini")


def main():
    if not os.path.isfile(INI):
        print("tools/local.ini is missing: copy tools/local.example.ini to tools/local.ini and set [paths] addons "
              "to your AddOns folder.")
        return 1
    cfg = configparser.ConfigParser()
    cfg.read(INI, encoding="utf-8")
    addons = cfg.get("paths", "addons", fallback="").strip()
    if not addons or "<" in addons:
        print("tools/local.ini has no real [paths] addons value (still the placeholder?).")
        return 1
    if not os.path.isdir(addons):
        print(f"The AddOns folder does not exist: {addons}")
        return 1
    target = os.path.join(addons, "AzGF_Probe")
    if os.path.isdir(target):
        shutil.rmtree(target)
    shutil.copytree(SOURCE, target)
    print(f"Installed AzGF_Probe into {target}. In game: /reload, then /agfp.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
