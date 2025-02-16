# RotFarm

This is beta test release for rot farm.

All it does is it will teleport around to find area with season event happening, walk around kill things ONLY, does not do any events or claim whisper cache.

It will also approach and interact cocoon if it sees it. Will stay around big cocoon to kill husks too.

Salvage only works with alfred so please get alfred.


Credits to Eletroluz for his helltide script that I used as a base


# Known problemms
The seasonal area buff detection is broken because it does not expire properly like helltide buff which makes your character continue staying in the area until it finishes one complete loop. The way to detect the changes is after every loop, we will go salvage with alfred and when it returns, the bugged season buff will disappear and it will search for new active season area
