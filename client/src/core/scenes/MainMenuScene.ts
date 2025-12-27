import Phaser from 'phaser';
export class MainMenuScene extends Phaser.Scene {
  constructor(){ super('MainMenu'); }
  create(){
    const t = this.add.text(400,220,'PATCHBOUND\nPress ENTER',{fontFamily:'monospace',fontSize:'18px'}); t.setOrigin(0.5);
    this.input.keyboard!.once('keydown-ENTER',()=> this.scene.start('Run'));
  }
}

