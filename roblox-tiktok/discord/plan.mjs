// What the Diamond Rush Discord server looks like: roles, channels, slowmodes,
// permissions, AutoMod rules and the posts. setup.mjs applies this plan.

// Discord permission bits.
export const P = {
  CREATE_INVITE: 1n << 0n,
  KICK: 1n << 1n,
  BAN: 1n << 2n,
  ADD_REACTIONS: 1n << 6n,
  VIEW_AUDIT_LOG: 1n << 7n,
  VIEW_CHANNEL: 1n << 10n,
  SEND_MESSAGES: 1n << 11n,
  MANAGE_MESSAGES: 1n << 13n,
  EMBED_LINKS: 1n << 14n,
  ATTACH_FILES: 1n << 15n,
  READ_HISTORY: 1n << 16n,
  MENTION_EVERYONE: 1n << 17n,
  CONNECT: 1n << 20n,
  SPEAK: 1n << 21n,
  MUTE_MEMBERS: 1n << 22n,
  MOVE_MEMBERS: 1n << 24n,
  USE_COMMANDS: 1n << 31n,
  MANAGE_THREADS: 1n << 34n,
  CREATE_PUBLIC_THREADS: 1n << 35n,
  SEND_IN_THREADS: 1n << 38n,
  MODERATE_MEMBERS: 1n << 40n,
};

const sum = (...bits) => bits.reduce((a, b) => a | b, 0n);

// What everyone may do by default: chat, react, share images and talk in voice.
// Not: ping @everyone, create invites (only the official invite is shared).
export const EVERYONE = sum(P.VIEW_CHANNEL, P.SEND_MESSAGES, P.READ_HISTORY, P.ADD_REACTIONS, P.ATTACH_FILES, P.EMBED_LINKS, P.CONNECT, P.SPEAK, P.USE_COMMANDS, P.SEND_IN_THREADS);

export const ROLES = [
  {
    key: 'moderator',
    name: 'Moderator',
    color: 0x3b82f6,
    hoist: true,
    permissions: sum(EVERYONE, P.KICK, P.BAN, P.VIEW_AUDIT_LOG, P.MANAGE_MESSAGES, P.MANAGE_THREADS, P.MODERATE_MEMBERS, P.MUTE_MEMBERS, P.MOVE_MEMBERS, P.MENTION_EVERYONE, P.CREATE_INVITE),
  },
  { key: 'streamer', name: 'Streamer', color: 0xe0b248, hoist: true, permissions: EVERYONE },
];

// Channel types: 4 category, 0 text, 2 voice.
// access: 'readonly' (only moderators post), 'staff' (only moderators see it), or open.
export const CHANNELS = [
  {
    category: 'START HERE',
    channels: [
      { key: 'rules', name: 'rules', access: 'readonly', topic: 'The server rules. Read these first.' },
      { key: 'announcements', name: 'announcements', access: 'readonly', topic: 'News about Diamond Rush and the TikTok connector.' },
    ],
  },
  {
    category: 'DOWNLOADS',
    channels: [
      { key: 'download', name: 'download-connector', access: 'readonly', topic: 'Download the Diamond Rush TikTok connector and set it up.' },
    ],
  },
  {
    category: 'COMMUNITY',
    channels: [
      { key: 'general', name: 'general', slowmode: 5, topic: 'Chat about Diamond Rush. Be kind.' },
      { key: 'clips', name: 'clips', slowmode: 30, topic: 'Share your best stream clips and wins.' },
      { key: 'voice', name: 'Lounge', type: 2 },
    ],
  },
  {
    category: 'SUPPORT',
    channels: [
      { key: 'help', name: 'help', slowmode: 30, topic: 'Questions about setting up the connector or the game.' },
      { key: 'bugs', name: 'bug-reports', slowmode: 3600, topic: 'One bug report per hour. Use the pinned template.' },
    ],
  },
  {
    category: 'STAFF',
    staff: true,
    channels: [
      { key: 'modlog', name: 'mod-log', access: 'staff', topic: 'AutoMod alerts and moderation notes.' },
    ],
  },
];

export function posts(downloadUrl) {
  const link = downloadUrl || '(the download link will be posted here soon)';
  return {
    rules: [
      '**Welcome to Diamond Rush!** Please follow these rules:',
      '',
      '**1.** Be kind. No harassment, hate speech, threats or bullying.',
      '**2.** Keep it family-friendly. No NSFW, gore or shocking content.',
      '**3.** No spam, no self-promotion and no server invites.',
      '**4.** Never share passwords, account details or personal information, yours or anyone else\'s.',
      '**5.** Nobody from this server will ever ask for your password or for Robux. Report anyone who does.',
      '**6.** Only download the connector from #download-connector.',
      '**7.** Follow the Discord Terms of Service and Community Guidelines, and the Roblox and TikTok rules.',
      '',
      'Moderators may remove messages or members who break these rules. Questions? Ask in #help.',
    ].join('\n'),
    download: [
      '**Diamond Rush TikTok connector**',
      '',
      `**Download:** ${link}`,
      '',
      '**1.** Download the ZIP, right-click it and choose **Extract All**.',
      '**2.** Go LIVE on TikTok, then double-click **DiamondRushBridge.exe**. Its page opens in your browser: type your TikTok username and press **Connect**.',
      '**3.** Copy the **game code** it shows.',
      '**4.** In the Roblox game, press **Y**, find **GAME CODE** and paste it.',
      '',
      'If Windows says "Windows protected your PC", click **More info**, then **Run anyway**.',
      'Problems? Ask in #help. Found a bug? Report it in #bug-reports.',
      '',
      'Only download the connector from this channel. We will never send it to you in a DM.',
    ].join('\n'),
    bugs: [
      '**How to report a bug** (you can post one report per hour)',
      '',
      '**What happened:**',
      '**What you expected to happen:**',
      '**Steps to make it happen again:**',
      '**Game or connector:**',
      '**Screenshot or clip** (if you can)',
    ].join('\n'),
    announcements: '**Welcome!** Diamond Rush news and connector updates will be posted here.',
  };
}

// AutoMod rules. Trigger types: 1 keyword, 3 spam, 4 keyword preset, 5 mention spam.
export const AUTOMOD = [
  { name: 'Block harmful words', trigger_type: 4, trigger_metadata: { presets: [1, 2, 3] } },
  { name: 'Block mention spam', trigger_type: 5, trigger_metadata: { mention_total_limit: 5, mention_raid_protection_enabled: true } },
  { name: 'Block suspected spam', trigger_type: 3 },
  {
    name: 'Block invites and scams',
    trigger_type: 1,
    trigger_metadata: {
      keyword_filter: ['*discord.gg/*', '*discord.com/invite*', '*free nitro*', '*free robux*', '*steamcommunity.com/gift*', '*nitro giveaway*'],
    },
  },
];

// Server-wide safety settings.
export const GUILD = {
  verification_level: 3, // high: verified email and 10 minutes on the server
  explicit_content_filter: 2, // scan media from everyone
  default_message_notifications: 1, // only @mentions
};
