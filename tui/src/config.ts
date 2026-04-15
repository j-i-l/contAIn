import { readFile, writeFile, mkdir } from 'fs/promises';
import { existsSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';

export interface AgentSystemConfig {
  name: string;
  type: 'opencode' | 'custom';
  enabled: boolean;
  container?: {
    name: string;
    image: string;
  };
  server?: {
    host: string;
    port: number;
  };
  custom?: {
    start_command?: string;
    stop_command?: string;
    status_command?: string;
    tui_command?: string;
  };
}

export interface ContAInConfig {
  primary_user: string;
  primary_home: string;
  project_paths: string[];
  agent_user: string;
  host: string;
  port: number;
  install_dir: string;
  agent_systems: Record<string, AgentSystemConfig>;
}

const DEFAULT_CONFIG: ContAInConfig = {
  primary_user: '',
  primary_home: '',
  project_paths: [],
  agent_user: 'agent',
  host: '127.0.0.1',
  port: 3000,
  install_dir: '/opt/contain',
  agent_systems: {
    opencode: {
      name: 'opencode',
      type: 'opencode',
      enabled: true,
      container: {
        name: 'contain',
        image: 'localhost/contain:latest'
      },
      server: {
        host: '127.0.0.1',
        port: 3000
      }
    }
  }
};

export class ConfigManager {
  private configPath: string;

  constructor(userHome?: string) {
    const home = userHome || homedir();
    this.configPath = join(home, '.config', 'contain', 'config.json');
  }

  async load(): Promise<ContAInConfig> {
    if (!existsSync(this.configPath)) {
      return DEFAULT_CONFIG;
    }
    try {
      const content = await readFile(this.configPath, 'utf-8');
      const parsed = JSON.parse(content);
      return { ...DEFAULT_CONFIG, ...parsed };
    } catch {
      return DEFAULT_CONFIG;
    }
  }

  async save(config: ContAInConfig): Promise<void> {
    const dir = dirname(this.configPath);
    if (!existsSync(dir)) {
      await mkdir(dir, { recursive: true });
    }
    await writeFile(this.configPath, JSON.stringify(config, null, 2) + '\n');
  }

  getConfigPath(): string {
    return this.configPath;
  }
}

export const configManager = new ConfigManager();