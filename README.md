# inne++ - the N++ discord server chatbot
***inne++*** is a chatbot for the N++ discord server #highscores channel. inne++ serves up a new level of the day in the channel at midnight MST (07:00 GMT) every night, as well as a new episode of the week every week on Friday at the same time.

inne++ also provides a bunch of commands for players to get high score data about themselves or other players, such as displaying counts of your highscores by rank, finding levels you haven't finished yet, finding levels you can easily improve on, and displaying top-N rankings across all players. In order to do this, inne++ downloads the scores once every half hour. If you'd like inne++ to update the stored scores for a specific level or episode immediately, you can simply request the scores in discord and inne++ will download the latest scores (and display them to you).

## Available commands

All commands can be sent to inne++ either via PM or in a public channel by mentioning @inne++ in the message. inne++ will respond via the same channel.
Commands generally aren't case-sensitive, except for the usernames.

### Display the level of the day/episode of the week
- *what is the level of the day?*
- *what is the episode of the week?*
- *what's the lotd*
- *what's the eotw*

inne++ will respond with the level of the day or the episode of the week.

### Display a screenshot of a level or episode
- *screenshot of <level>*

inne++ will respond with a picture of the requested level or episode.

'level' can be a level or episode ID (eg. SI-A-00, SI-A-00-00) or a level name (eg. supercomplexity).

### Display scores for a level or episode
- *scores for <level>*

inne++ will respond with the high scores table for the given level or episode.

'level' can be a level or episode ID (eg. SI-A-00, SI-A-00-00) or a level name (eg. supercomplexity).

This will also force inne++ to update the scores with the latest results from N++ (rather than waiting for the default half-hour between updates).

### Display time until a new episode or level
- *when's the next level*
- *when's the next lotd*
- *when's the next episode*
- *when's the next eotw*

inne++ will respond with a rough estimate of how long until a new level or episode is posted.

### Identify yourself
- *my name is \<username\>*

inne++ will save your username, so you don't need to specify it when looking up high score data with the following commands.
For any command that requires a username, if you don't specify a username, inne++ will use this one.

### Display top N rankings
- *rankings*
- *0th rankings*
- *top 10 rankings*
- *0th rankings with ties*
- *top 10 rankings with ties*

inne++ will compute the overall number of top-N scores for every player, and display the top 20.

If 'with ties' is specified, inne++ will consider a tie for the score to count towards the rankings, even if that means taking more than N rankings for the level.

### Display point rankings
- *point rankings*

inne++ will compute the total number of points for all players, and display the top 20.

Points are computed by giving players 20 points for 0th rankings, 19 for 1st, etc.

### Display your points
- *points*
- *points for <username>*

inne++ will tell you how many points you have (see 'point rankings' above).

If no username is specified, inne++ will use the one you specified earlier.

### Find a level ID by level name
- *level id for <level>*

inne++ will tell you the level ID for the specified level (eg. S-D-15-04 for 'supercomplexity').

### Find the name of a level by ID
- *level name for <level>*

inne++ will tell you the name of the specified level (eg. 'supercomplexity' for S-D-15-04)

### Display your top N count
- *how many*
- *how many 0ths*
- *how many top 10s*
- *how many top 10s with ties*
- *how many top 10s for \<username\>*

inne++ will display the number of top-N scores you have.

If no rank is specified, defaults to 0ths.

If no username is specified, uses the one you specified earlier.

### Display scores with the largest or smallest spread between 0th and Nth
- *spread*
- *spread 19th*
- *smallest spread*
- *biggest spread*
- *level spread*
- *episode spread*
- *biggest level spread 19th*

inne++ will display the episodes or levels with smallest or largest spread between 0th and Nth.

If a number (eg. 10th, 19th) is not specified, inne++ defaults to spread between 0th and 1st.

If 'smallest' or 'biggest' is not specified, inne++ defaults to 'biggest'.

If 'episode' or 'level' is not specified, inne++ defaults to 'level'.

### Display high score stats
- *stats for \<username\>*
- *stats*

inne++ will display the total number of level and episode high scores for the specified user, broken down by rank, and also a histogram of the player's scores.

If a username isn't specified, inne++ will use the one you specified earlier with the 'my name is' command.

### Display your most improvable scores
- *worst for \<username\>*
- *worst*
- *worst 20*
- *worst 20 for \<username\>*
- *worst 20 episodes*
- *worst 20 episodes for \<username\>*
- *worst 20 levels*

inne++ will display a list of your N most improvable level or episode scores (eg. your scores which are furthest from 0th), along with the spread for each. inne++ will also display a list of N levels or episodes on which you do not have a high score.

If a number isn't specified, inne++ defaults to 10.

If a username isn't specified, inne++ will use the one you specified earlier with the 'my name is' command.

If neither 'levels' or 'episodes' is specified, inne++ defaults to level scores.

### Display a list of levels you haven't high scored
- *missing for \<username\>*
- *missing*
- *missing 0ths*
- *missing episode top 10s*

inne++ will send you a text file containing all levels and episodes you're below the specified rank on.

If a username isn't specified, inne++ will use the one you specified earlier.

If a rank isn't specified, inne++ defaults to top 20.

### Display a list of all your high scores
- *list*
- *list for \<username\>*

inne++ will send you a text file containing all level and episode high scores for the specified user listed by rank.

If a username isn't specified, inne++ will use the one you specified earlier.

### Initialize inne++
- *hello*
- *hi*

When inne++ first joins a channel, in order to start sending levels and episodes of the day, you have to say hi. Note that if you run this in a private message before you run it in the channel, inne++ will send the levels/episodes to your PMs instead of the channel, so don't do that ;)

### Display help
- *help*
- *commands*

inne++ will send you a short form of this README file.

## License and attributions
This project is licensed under the terms of the MIT license (see LICENSE.txt in the root directory of the project).

Special thanks to jg9000, eru_bahagon and EddyMataGallos from the N forums for their work on NHigh (https://forum.droni.es/viewtopic.php?f=79&t=10472), which inspired most of the high-scoring features in inne++, and provided key guidance on using the N high scores API.