import { exec, spawn } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export interface ContainerStatus {
  running: boolean;
  name: string;
  image: string;
  status: string;
  uptime?: string;
}

function sudoExec(command: string, password?: string): Promise<{ stdout: string; stderr: string }> {
  if (!password) {
    return execAsync(`sudo ${command}`);
  }
  return new Promise((resolve, reject) => {
    const child = spawn('sudo', ['-S', 'sh', '-c', command], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d: Buffer) => { stdout += d.toString(); });
    child.stderr.on('data', (d: Buffer) => {
      const s = d.toString();
      // Filter out the sudo password prompt from stderr
      if (!s.includes('[sudo]') && !s.includes('password for')) {
        stderr += s;
      }
    });
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(new Error(stderr || `Command exited with code ${code}`));
      }
    });
    child.on('error', reject);
    child.stdin.write(password + '\n');
    child.stdin.end();
  });
}

export class PodmanService {
  private containerName: string;
  private imageName: string;
  private sudoPassword?: string;

  constructor(containerName: string, imageName: string) {
    this.containerName = containerName;
    this.imageName = imageName;
  }

  setSudoPassword(password: string): void {
    this.sudoPassword = password;
  }

  async getStatus(): Promise<ContainerStatus> {
    try {
      const { stdout } = await sudoExec(
        `systemctl is-active ${this.containerName}.service 2>/dev/null || echo inactive`,
        this.sudoPassword
      );
      const state = stdout.trim();
      const running = state === 'active';
      
      return {
        running,
        name: this.containerName,
        image: this.imageName,
        status: state,
      };
    } catch {
      return { running: false, name: this.containerName, image: this.imageName, status: 'unknown' };
    }
  }

  async start(): Promise<void> {
    const { stderr } = await sudoExec(
      `systemctl start ${this.containerName}.service`,
      this.sudoPassword
    );
    if (stderr) {
      throw new Error(stderr);
    }
  }

  async stop(): Promise<void> {
    const { stderr } = await sudoExec(
      `systemctl stop ${this.containerName}.service`,
      this.sudoPassword
    );
    if (stderr) {
      throw new Error(stderr);
    }
  }

  async restart(): Promise<void> {
    await this.stop();
    await this.start();
  }

  async logs(tail: number = 50): Promise<string> {
    try {
      const { stdout } = await sudoExec(
        `journalctl -u ${this.containerName}.service --no-pager -n ${tail} 2>&1`,
        this.sudoPassword
      );
      return stdout || 'No logs available';
    } catch (err) {
      return `Error fetching logs: ${(err as Error).message}`;
    }
  }

  async commit(): Promise<void> {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const newImage = `${this.imageName}:${timestamp}`;

    await sudoExec(
      `podman commit ${this.containerName} ${newImage}`,
      this.sudoPassword
    );
    await sudoExec(
      `podman tag ${newImage} ${this.imageName}`,
      this.sudoPassword
    );
  }
}
