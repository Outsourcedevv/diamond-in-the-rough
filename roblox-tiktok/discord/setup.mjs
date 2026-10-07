// Sets up a Diamond Rush Discord server in one go.
// Run:  node setup.mjs        (it asks for the server ID, bot token and download link)
// Or:   node setup.mjs --dry-run   to see what it would do without touching Discord.
// See README.md for creating the server and the bot first.
import readline from 'node:readline';
import { CHANNELS, ROLES, AUTOMOD, GUILD, EVERYONE, P, posts } from './plan.mjs';

const API = 'https://discord.com/api/v10';
const dryRun = process.argv.includes('--dry-run');

function ask(question, hidden = false) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (hidden) {
      rl._writeToOutput = (text) => {
        if (text.includes(question)) rl.output.write(text);
        else rl.output.write('*');
      };
    }
    rl.question(question, (answer) => {
      rl.close();
      if (hidden) process.stdout.write('\n');
      resolve(answer.trim());
    });
  });
}

let token = process.env.DISCORD_TOKEN || '';
let requests = 0;

async function api(method, route, body) {
  requests += 1;
  if (dryRun) {
    console.log(`  ${method} ${route}${body ? ' ' + JSON.stringify(body).slice(0, 140) : ''}`);
    return { id: `dry-${requests}`, roles: [{ id: 'everyone', name: '@everyone' }], features: [] };
  }
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const response = await fetch(API + route, {
      method,
      headers: { authorization: `Bot ${token}`, 'content-type': 'application/json', 'user-agent': 'DiamondRushSetup (https://github.com, 1.0)' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (response.status === 429) {
      const wait = Number((await response.json()).retry_after ?? 1);
      await new Promise((r) => setTimeout(r, (wait + 0.25) * 1000));
      continue;
    }
    if (response.status === 204) return {};
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(`${method} ${route} failed (${response.status}): ${JSON.stringify(data)}`);
      error.status = response.status;
      error.code = data.code;
      throw error;
    }
    return data;
  }
  throw new Error(`${method} ${route}: Discord kept asking us to slow down`);
}

const overwrite = (id, allow, deny) => ({ id, type: 0, allow: String(allow), deny: String(deny) });

async function main() {
  console.log('\nDiamond Rush Discord setup\n');
  const guildId = dryRun ? 'GUILD' : await ask('Server ID (right-click the server icon > Copy Server ID): ');
  if (!dryRun && !token) token = await ask('Bot token (hidden as you paste): ', true);
  const downloadUrl = dryRun ? '' : await ask('Connector download link (press Enter to add it later): ');
  if (!dryRun && (!/^\d{15,22}$/.test(guildId) || token.length < 30)) {
    console.log('That server ID or token does not look right. See README.md.');
    process.exit(1);
  }

  // Check the token and that the bot is really in this server before changing anything.
  if (!dryRun) {
    const me = await api('GET', '/users/@me');
    const servers = await api('GET', '/users/@me/guilds');
    console.log(`Logged in as the bot "${me.username}".`);
    if (!servers.some((server) => server.id === guildId)) {
      console.log(`\nThe bot "${me.username}" is not in the server with ID ${guildId}.`);
      if (servers.length > 0) {
        console.log('It is in these servers:');
        for (const server of servers) console.log(`  ${server.name}  (ID ${server.id})`);
        console.log('If one of these is the right one, run the tool again with that ID.');
      } else {
        console.log('It is not in any server yet.');
      }
      console.log('To add it: Developer Portal > your bot > OAuth2 > URL Generator > tick "bot" and "Administrator" > open the link > pick your server > Authorize.');
      console.log('Also check that the ID is the server\'s (right-click the server icon > Copy Server ID), and that the token is from this same bot.\n');
      process.exit(1);
    }
  }
  const guild = await api('GET', `/guilds/${guildId}`);
  const everyoneId = dryRun ? 'everyone' : guildId; // @everyone's role ID is the server ID
  console.log(`Setting up ${guild.name ?? 'the server'}...`);

  // Roles: reuse ones with the same name if the tool runs twice.
  const roles = {};
  for (const role of ROLES) {
    const existing = (guild.roles ?? []).find((r) => r.name === role.name);
    roles[role.key] = existing ?? (await api('POST', `/guilds/${guildId}/roles`, { name: role.name, color: role.color, hoist: role.hoist, permissions: String(role.permissions), mentionable: false }));
    console.log(`  role ${role.name}`);
  }
  await api('PATCH', `/guilds/${guildId}/roles/${everyoneId}`, { permissions: String(EVERYONE) });
  const mod = roles.moderator.id;

  // Channels.
  const existing = dryRun ? [] : await api('GET', `/guilds/${guildId}/channels`);
  const find = (name, type, parent) => existing.find((c) => c.name === name && c.type === type && (parent === undefined || c.parent_id === parent));
  const made = {};
  for (const [index, group] of CHANNELS.entries()) {
    const categoryOverwrites = group.staff ? [overwrite(everyoneId, 0n, P.VIEW_CHANNEL), overwrite(mod, P.VIEW_CHANNEL, 0n)] : [];
    const category = find(group.category, 4) ?? (await api('POST', `/guilds/${guildId}/channels`, { name: group.category, type: 4, position: index, permission_overwrites: categoryOverwrites }));
    for (const channel of group.channels) {
      const type = channel.type ?? 0;
      const overwrites = [...categoryOverwrites];
      if (channel.access === 'readonly') {
        overwrites.push(overwrite(everyoneId, 0n, P.SEND_MESSAGES | P.CREATE_PUBLIC_THREADS | P.SEND_IN_THREADS), overwrite(mod, P.SEND_MESSAGES, 0n));
      }
      const body = { name: channel.name, type, parent_id: category.id, permission_overwrites: overwrites };
      if (type === 0) {
        body.topic = channel.topic ?? '';
        body.rate_limit_per_user = channel.slowmode ?? 0;
      }
      // Reuse a channel with this name anywhere (such as Discord's default #general) and move it here.
      let found = find(channel.name, type);
      if (found) found = await api('PATCH', `/channels/${found.id}`, body);
      made[channel.key] = found ?? (await api('POST', `/guilds/${guildId}/channels`, body));
      const slow = channel.slowmode ? `  (slowmode ${channel.slowmode >= 3600 ? channel.slowmode / 3600 + ' hour' : channel.slowmode + ' s'})` : '';
      console.log(`  #${channel.name}${slow}`);
    }
  }

  // Tidy away Discord's default "Text Channels" and "Voice Channels" groups.
  if (!dryRun) {
    const now = await api('GET', `/guilds/${guildId}/channels`);
    for (const category of now.filter((c) => c.type === 4 && ['Text Channels', 'Voice Channels'].includes(c.name))) {
      for (const child of now.filter((c) => c.parent_id === category.id && c.type === 2 && c.name === 'General')) {
        await api('DELETE', `/channels/${child.id}`);
      }
      const left = (await api('GET', `/guilds/${guildId}/channels`)).filter((c) => c.parent_id === category.id);
      if (left.length === 0) await api('DELETE', `/channels/${category.id}`);
    }
  }

  // Posts, pinned.
  const text = posts(downloadUrl);
  for (const key of ['rules', 'download', 'bugs', 'announcements']) {
    const message = await api('POST', `/channels/${made[key].id}/messages`, { content: text[key], allowed_mentions: { parse: [] } });
    await api('PUT', `/channels/${made[key].id}/pins/${message.id}`);
  }
  console.log('  posted and pinned the rules, download steps, bug template and welcome');

  // Safety settings.
  await api('PATCH', `/guilds/${guildId}`, GUILD);
  console.log('  verification level High, media scanning for everyone, notifications @mentions only');

  // AutoMod: block the message and alert the moderators.
  const currentRules = dryRun ? [] : await api('GET', `/guilds/${guildId}/auto-moderation/rules`);
  for (const rule of AUTOMOD) {
    if (currentRules.some((r) => r.name === rule.name)) continue;
    try {
      await api('POST', `/guilds/${guildId}/auto-moderation/rules`, {
        ...rule,
        event_type: 1,
        enabled: true,
        actions: [{ type: 1, metadata: { custom_message: 'This message was blocked by AutoMod.' } }, { type: 2, metadata: { channel_id: made.modlog.id } }],
        exempt_roles: [mod],
      });
      console.log(`  AutoMod: ${rule.name}`);
    } catch (error) {
      console.log(`  AutoMod: ${rule.name} skipped (${error.message.slice(0, 120)})`);
    }
  }

  // Community: the Rules screen new members must accept, and safety alerts.
  try {
    await api('PATCH', `/guilds/${guildId}`, {
      features: [...new Set([...(guild.features ?? []), 'COMMUNITY'])],
      rules_channel_id: made.rules.id,
      public_updates_channel_id: made.modlog.id,
      safety_alerts_channel_id: made.modlog.id,
    });
    console.log('  Community turned on (rules screen and safety alerts)');
  } catch (error) {
    console.log(`  Community could not be turned on automatically; turn it on in Server Settings > Enable Community. (${error.message.slice(0, 100)})`);
  }

  console.log(`\nDone in ${requests} steps.`);
  console.log('Last steps by hand (see README.md): give yourself the Moderator role, turn on "Require 2FA for moderator actions",');
  console.log('make a never-expiring invite from #rules, then remove the setup bot from the server.\n');
}

main().catch((error) => {
  console.error(`\nSetup stopped: ${error.message}`);
  if (error.status === 401) console.error('The bot token is wrong. Copy it again from the Developer Portal (Bot > Reset Token).');
  if (error.code === 50001) console.error('The bot cannot see that server or channel: it is not in the server, or the server ID is wrong.');
  else if (error.code === 60003) console.error('Your server requires 2FA for moderator actions. Turn on 2FA on the bot owner\'s account, or switch that setting off until setup is done.');
  else if (error.status === 403) console.error('The bot is missing a permission. In Server Settings > Roles, give the bot\'s role Administrator and drag it to the top, then run again.');
  if (error.status === 404) console.error('The server ID is wrong, or the bot is not in that server yet.');
  process.exit(1);
});
