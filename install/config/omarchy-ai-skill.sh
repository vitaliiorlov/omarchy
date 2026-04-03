# Place in ~/.claude/skills since all tools populate from there as well as their own sources
mkdir -p ~/.claude/skills
ln -sf $OMARCHY_PATH/default/omarchy-skill ~/.claude/skills/omarchy
ln -sf $OMARCHY_PATH/default/omarchy-fork-update-skill ~/.claude/skills/omarchy-fork-update
