# youtube

Read YouTube livestream chats, inside your Chatterino!

## Setup Instructions

1. **Install the Plugin**
   - Place the `youtube` folder into your Chatterino `Plugins` directory.
   - Ensure `init.lua` and `info.json` are present in the `youtube` folder.
   - Restart Chatterino or enable the plugin from the Plugins menu.

2. **Grant Permissions**
   - This plugin requires the following permissions (configured in `info.json`):
     - `Network`: Allows the plugin to fetch YouTube chat data.
     - `FilesystemRead`: Allows reading configuration and data files.
     - `FilesystemWrite`: Allows saving and updating plugin data.

## How to Use

### Adding a YouTube Chat to a Channel

- In any Chatterino channel, type:

  ```
  /youtube https://www.youtube.com/@Username/live
  ```

  or

  ```
  /youtube https://www.youtube.com/channel/CHANNEL_ID/live
  ```

- **Note:** The URL must start with `https://www.youtube.com/`.
- The channel you run the command in will display the YouTube chat when the stream is live.
- You can add multiple YouTube chats to different Chatterino channels.

### Example Usage

- To add the chat for a specific YouTube channel:
  ```
  /youtube https://www.youtube.com/@LinusTechTips/live
  ```
- To add by channel ID:
  ```
  /youtube https://www.youtube.com/channel/UCXuqSBlHAE6Xw-yeJA0Tunw/live
  ```

### Removing a YouTube Chat

- To remove a YouTube chat from the current split/channel, type:
  ```
  /youtube-stop
  ```
- This will stop displaying the YouTube chat in that split. If no YouTube chat is active, you will see a message.
- To remove a YouTube chat, simply close the Chatterino split/channel where it was added.
- The plugin will automatically stop polling for that chat if no splits are using it.

## Troubleshooting

- If you see a message like `[youtube] No URL provided!`, make sure you include a valid YouTube URL after the command.
- If you see `[youtube] Not valid YouTube URL: ...`, check that your URL starts with `https://www.youtube.com/`.
- If the chat does not appear, ensure the YouTube stream is live and the URL is correct.

## Features

- Innertube-only.
- Add YouTube channels via `https://www.youtube.com/@Username/live` or `https://www.youtube.com/channel/.../live` to add offline YouTube channels and render their chat once stream is live.
- Offline polling every 1 second.
- Youtube chats can be added to multiple Chatterino channels, the polling will add YouTube chat to the relevant Chatterino channels without extra polling.

## Credits

Thanks to @mm2pl and @nerixyz, they were big help.

MIT
