# MxBridge – Matrix-XMPP-Bridge

A non-puppeting (i.e. bot) bridge between Matrix and XMPP group chats.

This application works by connecting as a user to a Matrix and an XMPP server. When it has been invited and the mapping between two rooms is set up, it joins those rooms and begins forwarding messages to the room connected on the other network.

## Installation

This is a standard Elixir application, but the recommended deployment is through Docker.

Make sure to checkout the source code repository first:

```bash
git clone https://github.com/djmaze/mxbridge
cd mxbridge
```

## Getting started

### Initial setup

1. Create a user on the Matrix server.
1. Create a user on the XMPP server.
1. Create an admin room on the Matrix server. (Maybe give the room a _local address_ so you can use its alias.) Invite the bot user to the room.
1. Create an admin room on the XMPP server. Invite the bot user to the room.
1. Copy `.env.sample` to `.env` and fill out the credentials (including the admin rooms) in `.env`.

    For the Matrix room, you can use either the room id (e.g. `!id:matrix.org`) or the alias (`#alias:matrix.org`).

1. Start the bridge:

        docker-compose up app

### Mapping a room

In order to map a room on both networks, you need to:

1. (Optional: Give the matrix room a local address alias for easier addressing.)
1. Invite the bot user to the Matrix room.
1. Invite the bot user to the XMPP room.
1. In the Matrix or the XMPP admin room, map the two rooms:

        map #foo:matrix.org foo@conference.xmpp.org

1. The bot should now be joining the room on both networks. It will begin to forward each message to the connected room.

## What's more?

There are some more commands available in the admin rooms. Try `help`.

## How does it work?

When starting up, the bot logs into both networks and immediately tries to join the networks. The room mappings are saved and loaded from the Matrix admin room's metadata. Thus the mappings will persist as long as the admin room in Matrix is present.

The bot then listens for new messages on both networks and forwards them to the connected channel, while prefixing each message with `[user]`.

There is some special handling for [HTTP file uploads](https://xmpp.org/extensions/xep-0363.html) on the XMPP side. The bot will download each file and post it as an upload in the Matrix room.

The handling for the Matrix => XMPP case currently is a bit weaker. Users on the XMPP side will just see the download link from the Matrix server. (Sorry, no real uploads / image previews for this case yet.)

## Credits

Bear with me, this is my first real Elixir project. So the code is probably far from perfect. Also, no tests currently, sorry.

Thanks to [Romeo](https://github.com/scrogson/romeo), the bulk of the XMPP work is being taken care of outside of this codebase.

The matrix client portion has been shamelessly copied and adapted from the [Bender](https://github.com/DylanGriffith/bender) framework. (We should build a library out of this!)

And thanks to the Elixir developers for making a language perfectly suited for this kind of software! :)
