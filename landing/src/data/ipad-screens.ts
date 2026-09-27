import consoleShot from '../assets/screens/console-ipad.png';
import terminalKeyboardShot from '../assets/screens/terminal-keyboard-ipad.png';
import skillsShot from '../assets/screens/skills-ipad.png';
import terminalShot from '../assets/screens/terminal-ipad.png';
import windowedShot from '../assets/screens/windowed-ipad.png';

export const ipadScreens = [
  {
    image: windowedShot,
    alt: 'Heeler in a floating iPad window',
    title: 'Fits your workspace',
    caption: 'Keep your agent console close in a flexible iPad window.',
  },
  {
    image: consoleShot,
    alt: 'Agent sidebar beside a Claude Code conversation and the Composer on iPad',
    title: 'Every Agent. One Console.',
    caption: 'Keep the Agent list visible alongside the selected conversation.',
  },
  {
    image: terminalKeyboardShot,
    alt: 'Direct Input with its shortcut row and the iOS keyboard on iPad',
    title: 'Type directly',
    caption: "Type straight into the Agent's terminal with Direct Input.",
  },
  {
    image: skillsShot,
    alt: "Agent Skills in the tools keyboard below an Agent's live terminal on iPad",
    title: 'Skills within reach',
    caption: 'Browse Agent Skills from the tools keyboard.',
  },
  {
    image: terminalShot,
    alt: 'Terminals sidebar and a Shell Terminal in Keys mode on iPad',
    title: 'A shell when you need one',
    caption: 'Open a plain terminal in any Workspace, with Text and Keys modes.',
  },
];
