import Phaser from 'phaser';
import { BootScene } from './scenes/BootScene';
import { MainMenuScene } from './scenes/MainMenuScene';
import { RunScene } from './scenes/RunScene';
export const GAME_WIDTH = 800; export const GAME_HEIGHT = 450;
export function createGame(parent: string){
  return new Phaser.Game({ type: Phaser.AUTO, width: GAME_WIDTH, height: GAME_HEIGHT, parent,
    pixelArt: true, backgroundColor: '#0f0f1a',
    physics: { default: 'arcade', arcade: { gravity: { x: 0, y: 0 }, debug: false } },
    scene: [BootScene, MainMenuScene, RunScene]
  });
}

