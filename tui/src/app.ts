import blessed from 'blessed';
import { ConfigManager, ContAInConfig, AgentSystemConfig } from './config.js';
import { PodmanService } from './services/podman.js';
import { OpenCodeService } from './services/opencode.js';

export interface AgentSystem {
  name: string;
  config: AgentSystemConfig;
  service: PodmanService | OpenCodeService | null;
}

export class App {
  private screen!: ReturnType<typeof blessed.screen>;
  private logoBox!: ReturnType<typeof blessed.box>;
  private leftPanel!: ReturnType<typeof blessed.box>;
  private rightPanel!: ReturnType<typeof blessed.box>;
  private statusBar!: ReturnType<typeof blessed.box>;
  private config: ContAInConfig | null = null;
  private agentSystems: Map<string, AgentSystem> = new Map();
  private selectedAS: string | null = null;
  private selectedAction: number = 0;
  private actions: string[] = ['status', 'start', 'stop', 'commit', 'logs', 'tui'];
  private sudoPassword: string | null = null;

  // ANSI escape codes for inline coloring
  private static readonly DG = '\x1b[90m';        // dark gray (letters)
  private static readonly PC = '\x1b[38;5;223m';  // pale cream (brackets)
  private static readonly RST = '\x1b[0m';

  private static readonly LOGO_LINES = [
    `                    ${App.PC}████${App.RST}     ${App.PC}████${App.RST}`,
    `                    ${App.DG}█${App.PC}█${App.RST}  ${App.DG}███${App.RST} ${App.DG}███${App.PC}██${App.RST}`,
    `                    ${App.DG}█${App.PC}█${App.RST} ${App.DG}█${App.RST}   ${App.DG}█${App.RST} ${App.DG}█${App.RST} ${App.PC}██${App.RST}`,
    `     ${App.DG}███${App.RST}  ${App.DG}███${App.RST} ${App.DG}██████████${App.RST}   ${App.DG}█${App.RST} ${App.DG}█${App.RST} ${App.PC}█${App.DG}████${App.RST}`,
    `    ${App.DG}█${App.RST}    ${App.DG}█${App.RST}   ${App.DG}██${App.RST}   ${App.DG}█${App.RST} ${App.DG}█${App.PC}█${App.RST} ${App.DG}█████${App.RST} ${App.DG}█${App.RST} ${App.PC}█${App.DG}█${App.RST}   ${App.DG}█${App.RST}`,
    `    ${App.DG}█${App.RST}    ${App.DG}█${App.RST}   ${App.DG}██${App.RST}   ${App.DG}█${App.RST} ${App.DG}█${App.PC}█${App.RST} ${App.DG}█${App.RST}   ${App.DG}█${App.RST} ${App.DG}█${App.RST} ${App.PC}█${App.DG}█${App.RST}   ${App.DG}█${App.RST}`,
    `    ${App.DG}█${App.RST}    ${App.DG}█${App.RST}   ${App.DG}██${App.RST}   ${App.DG}█${App.RST} ${App.DG}█${App.PC}█${App.RST} ${App.DG}█${App.RST}   ${App.DG}█${App.RST} ${App.DG}█${App.RST} ${App.PC}█${App.DG}█${App.RST}   ${App.DG}█${App.RST}`,
    `     ${App.DG}███${App.RST}  ${App.DG}███${App.RST} ${App.DG}█${App.RST}   ${App.DG}█${App.RST} ${App.DG}████${App.RST}   ${App.DG}████${App.PC}█${App.DG}█${App.RST}   ${App.DG}█${App.RST}`,
    `                    ${App.PC}████${App.RST}     ${App.PC}████${App.RST}`,
  ];

  async init(): Promise<void> {
    this.config = await new ConfigManager().load();

    this.createUI();
    this.loadAgentSystems();
    this.setupUI();
    this.setupKeys();
    this.render();
  }

  private createUI(): void {
    this.screen = blessed.screen({
      smartCSR: true,
      title: 'cont[AI]n TUI',
      fullUnicode: true,
    });

    this.logoBox = blessed.box({
      width: '100%',
      height: 10,
      left: 0,
      top: 0,
      content: App.LOGO_LINES.join('\n'),
    });

    this.leftPanel = blessed.box({
      width: '30%',
      height: '100%-13',
      left: 0,
      top: 10,
      border: { type: 'line', fg: 'cyan' } as any,
      style: { border: { fg: 'cyan' } },
    });

    this.rightPanel = blessed.box({
      width: '70%',
      left: '30%',
      top: 10,
      height: '100%-13',
      border: { type: 'line', fg: 'green' } as any,
      style: { border: { fg: 'green' } },
    });

    this.statusBar = blessed.box({
      bottom: 0,
      height: 3,
      width: '100%',
      style: { bg: 'blue', fg: 'white' },
      content: '\u2191/\u2193: Navigate | Enter: Select | Esc: Back | q: Quit',
    });
  }

  private loadAgentSystems(): void {
    if (!this.config) return;

    for (const [name, asConfig] of Object.entries(this.config.agent_systems)) {
      if (!asConfig.enabled) continue;

      let service: PodmanService | OpenCodeService | null = null;

      if (asConfig.type === 'opencode' && asConfig.container && asConfig.server) {
        service = new PodmanService(asConfig.container.name, asConfig.container.image);
      }

      this.agentSystems.set(name, { name, config: asConfig, service });
    }

    if (this.agentSystems.size > 0) {
      this.selectedAS = this.agentSystems.keys().next().value || null;
    }
  }

  private setupUI(): void {
    this.screen.append(this.logoBox);
    this.screen.append(this.leftPanel);
    this.screen.append(this.rightPanel);
    this.screen.append(this.statusBar);
    this.render();
  }

  private setupKeys(): void {
    this.screen.key(['up', 'k'], () => this.navigateUp());
    this.screen.key(['down', 'j'], () => this.navigateDown());
    this.screen.key(['enter'], () => this.executeAction());
    this.screen.key(['escape', 'q'], () => this.quit());
    this.screen.key(['q'], () => this.quit());
  }

  private navigateUp(): void {
    if (this.selectedAS) {
      const as = this.agentSystems.get(this.selectedAS);
      if (as?.config.type === 'opencode') {
        this.selectedAction = Math.max(0, this.selectedAction - 1);
      }
    } else {
      const keys = Array.from(this.agentSystems.keys());
      const idx = keys.indexOf(this.selectedAS || '');
      if (idx > 0) {
        this.selectedAS = keys[idx - 1];
        this.selectedAction = 0;
      }
    }
    this.render();
  }

  private navigateDown(): void {
    if (this.selectedAS) {
      const as = this.agentSystems.get(this.selectedAS);
      if (as?.config.type === 'opencode') {
        this.selectedAction = Math.min(this.actions.length - 1, this.selectedAction + 1);
      }
    } else {
      const keys = Array.from(this.agentSystems.keys());
      const idx = keys.indexOf(this.selectedAS || '');
      if (idx < keys.length - 1) {
        this.selectedAS = keys[idx + 1];
        this.selectedAction = 0;
      }
    }
    this.render();
  }

  private async executeAction(): Promise<void> {
    if (!this.selectedAS) return;

    const as = this.agentSystems.get(this.selectedAS);
    if (!as || !as.service) return;

    const action = this.actions[this.selectedAction];

    if (as.config.type === 'opencode' && as.service instanceof PodmanService) {
      // Ensure we have sudo password before running any action
      if (!this.sudoPassword) {
        const password = await this.promptSudoPassword();
        if (!password) return; // User cancelled
        this.sudoPassword = password;
      }
      as.service.setSudoPassword(this.sudoPassword);
      await this.handleOpenCodeAction(as.service, action);
    }

    this.render();
  }

  private promptSudoPassword(): Promise<string | null> {
    return new Promise((resolve) => {
      const overlay = blessed.box({
        parent: this.screen,
        top: 'center',
        left: 'center',
        width: 50,
        height: 7,
        border: { type: 'line' },
        style: {
          border: { fg: 'yellow' },
          bg: 'black',
        },
        tags: true,
      } as any);

      blessed.text({
        parent: overlay,
        top: 0,
        left: 1,
        content: '  sudo password required',
        style: { fg: 'yellow', bg: 'black' },
      } as any);

      const input = blessed.textbox({
        parent: overlay,
        top: 2,
        left: 1,
        right: 1,
        height: 1,
        censor: true,
        style: {
          fg: 'white',
          bg: 'black',
          focus: { fg: 'white', bg: 'black' },
        },
        inputOnFocus: true,
      } as any);

      blessed.text({
        parent: overlay,
        top: 4,
        left: 1,
        content: '  Enter: confirm | Esc: cancel',
        style: { fg: 'gray', bg: 'black' },
      } as any);

      input.on('submit', (value: string) => {
        overlay.destroy();
        this.screen.render();
        resolve(value || null);
      });

      input.on('cancel', () => {
        overlay.destroy();
        this.screen.render();
        resolve(null);
      });

      input.key('escape', () => {
        overlay.destroy();
        this.screen.render();
        resolve(null);
      });

      this.screen.render();
      input.focus();
    });
  }

  private async handleOpenCodeAction(service: PodmanService, action: string): Promise<void> {
    try {
      switch (action) {
        case 'status':
          const status = await service.getStatus();
          const statusMsg = [
            `Container: ${status.name}`,
            `Image: ${status.image}`,
            `Status: ${status.status}`,
          ].join('\n          ');
          this.showMessage(statusMsg, status.running ? 'green' : 'red');
          break;
        case 'start':
          await service.start();
          this.showMessage('Container started', 'green');
          break;
        case 'stop':
          await service.stop();
          this.showMessage('Container stopped', 'yellow');
          break;
        case 'commit':
          await service.commit();
          this.showMessage('Container committed', 'cyan');
          break;
        case 'logs':
          const logs = await service.logs();
          this.showLogs(logs);
          break;
        case 'tui':
          this.launchOpenCodeTUI();
          break;
      }
    } catch (err) {
      const msg = (err as Error).message || '';
      // If sudo auth failed, clear cached password so user is prompted again
      if (msg.includes('incorrect password') || msg.includes('try again') || msg.includes('authentication failure')) {
        this.sudoPassword = null;
      }
      this.showMessage(`Error: ${msg}`, 'red');
    }
  }

  private launchOpenCodeTUI(): void {
    this.showMessage('Launching OpenCode TUI...', 'cyan');

    setTimeout(async () => {
      this.screen.destroy();
      const { spawn } = await import('child_process');

      // Cache sudo credentials first (if we have a password), then launch
      // the real command with stdio: 'inherit' for proper PTY pass-through.
      if (this.sudoPassword) {
        await this.cacheSudoCredentials(this.sudoPassword);
      }

      // Launch with full stdio inheritance so the interactive TUI gets
      // proper PTY, raw mode, mouse events, and terminal size signals.
      const child = spawn('sudo', [
        'podman', 'exec', '-it', '--user', 'agent',
        '-e', 'HOME=/home/agent',
        '-e', 'XDG_CONFIG_HOME=/home/agent/.config',
        '-e', 'XDG_DATA_HOME=/home/agent/.local/share',
        '-e', 'XDG_STATE_HOME=/home/agent/.local/state',
        'contain', 'sh', '-c', 'umask 002 && exec opencode-tui "$@"', '--',
      ], {
        stdio: 'inherit',
      });
      child.on('close', (code) => {
        process.exit(code ?? 0);
      });
    }, 1000);
  }

  /**
   * Cache sudo credentials by running `sudo -v` with the password piped via stdin.
   * After this succeeds, subsequent `sudo` calls within the timeout window
   * will not prompt for a password, allowing `stdio: 'inherit'` on the real command.
   */
  private async cacheSudoCredentials(password: string): Promise<void> {
    const { spawn } = await import('child_process');
    return new Promise((resolve, reject) => {
      const child = spawn('sudo', ['-S', '-v'], {
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      child.on('close', (code: number) => {
        if (code === 0) {
          resolve();
        } else {
          reject(new Error('Failed to cache sudo credentials'));
        }
      });
      child.on('error', reject);
      child.stdin!.write(password + '\n');
      child.stdin!.end();
    });
  }

  private showMessage(msg: string, color: string = 'white'): void {
    this.rightPanel.setContent(`
${' '.repeat(10)}${msg}
${' '.repeat(10)}Press any key to continue...
    `.trim());
    this.screen.render();

    this.screen.once('key', () => {
      this.render();
    });
  }

  private showLogs(logs: string): void {
    const logBox = blessed.box({
      width: '100%',
      height: '100%',
      border: { type: 'line', fg: 'yellow' },
      scrollable: true,
      alwaysScroll: true,
    } as any);

    logBox.setContent(logs || 'No logs available');
    this.rightPanel.append(logBox);
    this.screen.render();

    this.screen.once('key', () => {
      this.rightPanel.remove(logBox);
      this.render();
    });
  }

  private render(): void {
    this.renderLeftPanel();
    this.renderRightPanel();
    this.screen.render();
  }

  private renderLeftPanel(): void {
    let content = '\n  Agent Systems\n\n';

    for (const [name, as] of this.agentSystems) {
      const prefix = name === this.selectedAS ? '▶ ' : '  ';
      const suffix = as.config.enabled ? ' [enabled]' : ' [disabled]';
      content += `${prefix}${name}${suffix}\n`;
    }

    this.leftPanel.setContent(content);
  }

  private renderRightPanel(): void {
    if (!this.selectedAS) {
      this.rightPanel.setContent('\n  Select an Agent System from the left panel.');
      return;
    }

    const as = this.agentSystems.get(this.selectedAS);
    if (!as) return;

    if (as.config.type === 'opencode') {
      let content = `\n  OpenCode Agent System\n\n`;
      content += `  Container: ${as.config.container?.name || 'N/A'}\n`;
      content += `  Image: ${as.config.container?.image || 'N/A'}\n`;
      content += `  Server: ${as.config.server?.host}:${as.config.server?.port}\n\n`;
      content += `  Actions:\n`;

      this.actions.forEach((action, idx) => {
        const prefix = idx === this.selectedAction ? '▶ ' : '  ';
        content += `  ${prefix}${action}\n`;
      });

      this.rightPanel.setContent(content);
    } else {
      this.rightPanel.setContent('\n  Custom Agent System\n');
    }
  }

  private quit(): void {
    this.screen.destroy();
    process.exit(0);
  }

  run(): void {
    this.screen.render();
  }
}