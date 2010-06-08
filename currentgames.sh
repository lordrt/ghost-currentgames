#! /bin/bash
#
# currentgames.sh v1.2
#
# Changelog v2.2
#  - support for private games (the bot immediately hops to the channel
#    after creating one, thus the p; q)
#  - support for renamimg the game with !pub, or !priv
#  - support for channel join
#
# Changelog v2.1
#  - added xml rss2 and json formats to the existing csv (.txt)
#
#
# This script looks for the current game in all ghost log files
# and appends it in a csv, xhtml and json files named
# 	$out.txt, $out.json and $out.xml respectively.
#
# It first check the log is not older than 60 seconds, or it will ignore it
# Then extracts the last "Waiting for X players line" and takes the game name from that
# Concatenates it to a tmp file (one line per bot)
# When all done, moves the tmp file to the webroot ($out.FORMAT)
#
# Once it works, put it into cron to run every 5 or 10 secs.
# */5 * * * * /path/to/currentgames.sh >/dev/null
#
# Note: this assumes all logs are on a single machine, and that logs reside
# in /home/ghost<X>/ghost.log. Change appropriately.
#
# Note #2: the script is deliberatly stateless to be simple, that's why it picks up only
# the last bit of action in the logs. I'm working on a more powerful perl/phyton
# script separatly.
#
# Feedback to <lordrt@6v6dota.org>, or on forum.ghostgraz.com
# Lincensed under the EU Public Lincese (either GPL2 or BSD terms, you choose)
# Feel free to modify so long as credit is given.

# settings
tmp=$(mktemp currentgames.XXXX)
out="/var/www/dota/depo/currentgames" # basename (.txt, .json and .xml will be added)
now=$(date +'%s')
rss_title="GHostGraz List of Current Games"
rss_url="http://ike.kiberpipa.org/dota/depo/currentgames.xml" # required for xml (rss) output
rss_now=$(date --rfc-2822)


# write the headers
echo -e "# list of current games on GhostGrat bots\n# created on $(date)" > $tmp.txt
cat > $tmp.xml <<EOD
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:media="http://search.yahoo.com/mrss/" xmlns:feedburner="http://rssnamespace.org/feedburner/ext/1.0" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
	<channel>
		<title>$rss_title</title>
		<description>forum.GHostGraz.com delivers up-to-the-5-second news and information on the latest games, bots, ppl required for the game to start and more (pun on cnn.com overhyped channel description).</description>
		<language>en-us</language>
		<copyright>ghostgraz.com</copyright>
		<pubDate>$rss_now</pubDate>
		<image>
			<title>$rss_title</title>
			<link>$rss_url</link>
			<url>http://forum.ghostgraz.com/dlattach/attach,1/type,avatar/</url>
			<width>65</width>
			<height>65</height>
			<description>forum.GHostGraz.com delivers up-to-the-5-second news and information on the latest games, bots, ppl required for the game to start and more (pun on cnn.com overhyped channel description).</description>
		</image>
		<link>$rss_url</link>
		<atom:link href="$rss_url" rel="self" type="application/rss+xml" />
EOD
echo -e '[' > $tmp.json


# process log files, generate body of all outputs
for log in /home/ike/ghostlj*/ghost.log /home/ghost*/ghost.log; do
	if [[ ! -f "$log" ]]; then
		continue
	fi

	modified=$(stat -c '%Y' $log)
	let "age=$now-$modified"
	if [[ $age -gt 60 ]]; then
		echo "WARN: Ignoring $log cause older than 60 sec (last modified $age sec ago)"
		continue
	fi

	bot=$(dirname $log | xargs basename)
	currentgame=$(tail -n 100 $log |\
		 sed -nre 's/.*\[GAME: ([^]]+)\] .*Waiting for ([0-9]) more players.*/\1,+\2/p;
			s@.*Creating public game \[([^]]+)\] started by \[([^]]+)\].*@\1,?@p;
			/Creating private game/{ s@.*Creating private game \[([^]]+)\] started by \[([^]]+)\].*@\1 priv by \2,?@p; q };
			s@.*\[GAME: ([^]]+)\] \[Local\]: Players still downloading the map.*@\1,+0@p
			s@.*\[GAME: ([^]]+)\] \[Local\]: Waiting to start until players have been pinged.*@\1,+0@p
			s@.*\[GAME: ([^]]+)\] .*Rehost was successful on at least one realm!*@\1,?@p
			s@.*\[BNET: [^]]+\] joined channel \[([^]]+)\]@in channel \1,-@p' | tail -1)

	gamename=$(echo $currentgame | cut -d "," -f 1)
	need=$(echo $currentgame | cut -d "," -f 2)
	if [[ -z "$currentgame" ]]; then
		gamename="-"
		need="-"
	fi
	if [[ -z "$need" ]]; then
		need="?"
	fi

	echo -e "$bot,$gamename,$need" >> $tmp.txt
	cat >> $tmp.xml <<EOD
		<item>
			<title>$gamename: $need</title>
			<description>
				$gamename&lt;br/&gt;&lt;br/&gt;
				
				Need $need. Copy, alt-tab to W3 and PLAY!&lt;br/&gt;
				Hosted by bot $bot.
			</description>
			<pubDate>$rss_now</pubDate>
			<guid isPermaLink="false">$gamename</guid>
		</item>
EOD
	cat >> $tmp.json <<EOD
	{ 
		"server" : "$bot",
		"gamename" : "$gamename",
		"need" : "$need"
	},
EOD
done


# add footers
cat >> $tmp.xml <<EOD
	</channel>
</rss>
EOD
sed -ri '$s/,\s*$//' $tmp.json # json does not like extra commas
echo -e ']' >> $tmp.json


# finalize
if [[ -s "$tmp.txt" ]]; then
	mv $tmp.txt $out.txt
	mv $tmp.json $out.json
	mv $tmp.xml $out.xml
	rm $tmp

	chmod o+r $out.*
	# baerli needs this
	if [[ $EUID -eq 0 ]]; then
		chown ghost:root $out.*
	fi

	exit 0
else
	echo "No games could be extracted from the logs, or no logs found" >&2
	exit 1
fi
