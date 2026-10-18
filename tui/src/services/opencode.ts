// SPDX-FileCopyrightText: 2024-2026 Jonas I. Liechti <j-i-l@t4d.ch>
//
// SPDX-License-Identifier: CC-BY-NC-4.0

export class OpenCodeService {
  constructor() {}

  async checkConnection(host: string, port: number): Promise<boolean> {
    try {
      // OpenCode v2 readiness endpoint. 200 means the API is up (no password
      // or valid auth); 401 means the API router is up behind auth. Both
      // prove liveness — only a connection failure or a non-API response
      // (server down / still booting) counts as not connected.
      const response = await fetch(`http://${host}:${port}/api/info`, {
        method: 'GET',
        signal: AbortSignal.timeout(2000),
      });
      return response.status === 200 || response.status === 401;
    } catch {
      return false;
    }
  }
}