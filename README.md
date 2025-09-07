# obs-source-search
A LUA script to search OBS sources and move them to the top

Useful for when you have multiple sources in a scene but only need a select few for a stream.

# How To use
Place the LUA script in the obs plugins scripts folder. The location is generally: C:\Program Files\obs-studio\data\obs-plugins\frontend-tools\scripts

Tools -> Scripts -> source_search.lua

- Select the correct scene.
- Enter the source name under search
- Pick the source you want under the matches dropdown
- Select "Move Selected Match To TOP"
- Hide All Sources will set all sources to not visible so you can toggle the ones you want on manually
