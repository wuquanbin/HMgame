import { BusinessError } from '@kit.BasicServicesKit';
import { connection, socket } from '@kit.NetworkKit';

const MQTT_CONNECT = 0x10;
const MQTT_CONNACK = 0x20;
const MQTT_PUBLISH = 0x30;
const MQTT_SUBSCRIBE = 0x82;
const MQTT_SUBACK = 0x90;
const MQTT_PINGREQ = 0xC0;
const MQTT_PINGRESP = 0xD0;
const MQTT_DISCONNECT = 0xE0;

const MQTT_WAIT_TIMEOUT_MS = 5000;

export interface MqttConfig {
  host: string;
  port: number;
  clientId: string;
  username?: string;
  password?: string;
  subscribeTopic: string;
  keepAlive: number;
}

export type MessageCallback = (topic: string, payload: string) => void;
export type StatusCallback = (message: string) => void;

class PendingWaiter {
  resolve: () => void = () => {};
  reject: (error: Error) => void = () => {};
  timer: number = -1;
}

export class MqttClient {
  private tcp: socket.TCPSocket | null = null;
  private config: MqttConfig;
  private connected: boolean = false;
  private messageCallback: MessageCallback | null = null;
  private statusCallback: StatusCallback | null = null;
  private pingTimer: number = -1;
  private packetId: number = 1;
  private pendingBuffer: Uint8Array = new Uint8Array(0);
  private connackWaiter: PendingWaiter | null = null;
  private subackWaiter: PendingWaiter | null = null;

  constructor(config: MqttConfig) {
    this.config = config;
  }

  isConnected(): boolean {
    return this.connected;
  }

  onMessage(callback: MessageCallback): void {
    this.messageCallback = callback;
  }

  onStatus(callback: StatusCallback): void {
    this.statusCallback = callback;
  }

  async connect(): Promise<void> {
    const addresses = await this.resolveHostAddresses();
    let lastErrorText = 'No address tried';

    for (let index = 0; index < addresses.length; index++) {
      try {
        await this.connectToAddress(addresses[index]);
        return;
      } catch (error) {
        lastErrorText = this.errorToText(error);
        this.disconnect();
        this.emitStatus('MQTT try failed: ' + addresses[index] + ' ' + lastErrorText);
      }
    }

    throw new Error(lastErrorText);
  }

  private connectToAddress(address: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      try {
        this.tcp = socket.constructTCPSocketInstance();
        this.bindSocketEvents();
        this.emitStatus('TCP connecting ' + address + ':' + this.config.port.toString());

        const options: socket.TCPConnectOptions = {
          address: {
            address: address,
            port: this.config.port,
            family: 1
          }
        };

        this.tcp.connect(options, async (err: BusinessError) => {
          if (err) {
            this.emitStatus('TCP connect failed: ' + this.errorToText(err));
            reject(err);
            return;
          }

          try {
            this.emitStatus('TCP connected, sending MQTT CONNECT');
            const connackPromise = this.waitForConnack();
            await this.tcpSend(this.buildConnectPacket());
            await connackPromise;
            this.connected = true;

            this.emitStatus('MQTT connected, subscribing ' + this.config.subscribeTopic);
            const subackPromise = this.waitForSuback();
            await this.subscribe(this.config.subscribeTopic);
            await subackPromise;

            this.startPing();
            this.emitStatus('Subscribed ' + this.config.subscribeTopic);
            resolve();
          } catch (error) {
            this.connected = false;
            this.emitStatus('MQTT connect failed: ' + this.errorToText(error));
            reject(error);
          }
        });
      } catch (error) {
        this.emitStatus('MQTT create socket failed: ' + this.errorToText(error));
        reject(error);
      }
    });
  }

  async publish(topic: string, payload: string): Promise<void> {
    if (!this.connected) {
      this.emitStatus('MQTT not connected, publish skipped');
      return;
    }
    await this.tcpSend(this.buildPublishPacket(topic, payload));
    this.emitStatus('Published ' + topic);
  }

  disconnect(): void {
    this.stopPing();
    this.clearWaiter(this.connackWaiter);
    this.clearWaiter(this.subackWaiter);
    this.connackWaiter = null;
    this.subackWaiter = null;

    if (this.connected && this.tcp !== null) {
      this.tcpSend(new Uint8Array([MQTT_DISCONNECT, 0x00]));
    }
    this.connected = false;

    if (this.tcp !== null) {
      try {
        this.tcp.close();
      } catch (error) {
        console.error('MQTT close failed: ' + this.errorToText(error));
      }
      this.tcp = null;
    }
  }

  private bindSocketEvents(): void {
    if (this.tcp === null) {
      return;
    }

    this.tcp.on('message', (value: socket.SocketMessageInfo) => {
      const data = new Uint8Array(value.message);
      this.handleIncomingData(data);
    });

    this.tcp.on('close', () => {
      this.connected = false;
      this.stopPing();
      this.emitStatus('MQTT socket closed');
    });

    this.tcp.on('error', (err: BusinessError) => {
      console.error('MQTT TCP error: ' + this.errorToText(err));
      this.connected = false;
      this.stopPing();
      this.emitStatus('MQTT TCP error: ' + this.errorToText(err));
    });
  }

  private async subscribe(topic: string): Promise<void> {
    await this.tcpSend(this.buildSubscribePacket(topic));
  }

  private buildConnectPacket(): Uint8Array {
    const clientId = this.config.clientId;
    const username = this.config.username || '';
    const password = this.config.password || '';
    const varHeader: number[] = [
      0x00, 0x04, 0x4D, 0x51, 0x54, 0x54,
      0x04,
      0x02,
      (this.config.keepAlive >> 8) & 0xFF, this.config.keepAlive & 0xFF
    ];
    const payload: number[] = [];

    this.pushUtf8(payload, clientId);
    if (username.length > 0) {
      varHeader[7] |= 0x80;
      this.pushUtf8(payload, username);
    }
    if (password.length > 0) {
      varHeader[7] |= 0x40;
      this.pushUtf8(payload, password);
    }
    return this.buildPacket(MQTT_CONNECT, varHeader, payload);
  }

  private buildSubscribePacket(topic: string): Uint8Array {
    const packetId = this.nextPacketId();
    const body: number[] = [
      (packetId >> 8) & 0xFF,
      packetId & 0xFF
    ];
    this.pushUtf8(body, topic);
    body.push(0x00);
    return this.buildPacket(MQTT_SUBSCRIBE, body, []);
  }

  private buildPublishPacket(topic: string, payloadText: string): Uint8Array {
    const topicBody: number[] = [];
    const payload: number[] = [];

    this.pushUtf8(topicBody, topic);
    this.pushRawString(payload, payloadText);
    return this.buildPacket(MQTT_PUBLISH, topicBody, payload);
  }

  private buildPacket(type: number, header: number[], payload: number[]): Uint8Array {
    const remaining = header.length + payload.length;
    const encodedLen = this.encodeRemainingLength(remaining);
    const packet = new Uint8Array(1 + encodedLen.length + remaining);
    let pos = 0;

    packet[pos++] = type;
    for (let index = 0; index < encodedLen.length; index++) {
      packet[pos++] = encodedLen[index];
    }
    for (let index = 0; index < header.length; index++) {
      packet[pos++] = header[index];
    }
    for (let index = 0; index < payload.length; index++) {
      packet[pos++] = payload[index];
    }
    return packet;
  }

  private encodeRemainingLength(length: number): number[] {
    const bytes: number[] = [];
    let value = length;
    do {
      let encodedByte = value % 128;
      value = Math.floor(value / 128);
      if (value > 0) {
        encodedByte |= 128;
      }
      bytes.push(encodedByte);
    } while (value > 0);
    return bytes;
  }

  private pushUtf8(target: number[], value: string): void {
    target.push((value.length >> 8) & 0xFF);
    target.push(value.length & 0xFF);
    this.pushRawString(target, value);
  }

  private pushRawString(target: number[], value: string): void {
    for (let index = 0; index < value.length; index++) {
      target.push(value.charCodeAt(index) & 0xFF);
    }
  }

  private tcpSend(data: Uint8Array): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (this.tcp === null) {
        resolve();
        return;
      }
      this.tcp.send({ data: data.buffer as ArrayBuffer }, (err: BusinessError) => {
        if (err) {
          reject(err);
          return;
        }
        resolve();
      });
    });
  }

  private startPing(): void {
    this.stopPing();
    this.pingTimer = setInterval(() => {
      if (this.connected) {
        this.tcpSend(new Uint8Array([MQTT_PINGREQ, 0x00]));
      }
    }, Math.floor(this.config.keepAlive * 500));
  }

  private stopPing(): void {
    if (this.pingTimer >= 0) {
      clearInterval(this.pingTimer);
      this.pingTimer = -1;
    }
  }

  private handleIncomingData(data: Uint8Array): void {
    const merged = new Uint8Array(this.pendingBuffer.length + data.length);
    let writePos = 0;
    for (let index = 0; index < this.pendingBuffer.length; index++) {
      merged[writePos++] = this.pendingBuffer[index];
    }
    for (let index = 0; index < data.length; index++) {
      merged[writePos++] = data[index];
    }

    let offset = 0;
    while (offset + 2 <= merged.length) {
      let pos = offset + 1;
      let remainingLen = 0;
      let multiplier = 1;
      let lengthReady = false;

      while (pos < merged.length) {
        const encodedByte = merged[pos++];
        remainingLen += (encodedByte & 0x7F) * multiplier;
        if ((encodedByte & 0x80) === 0) {
          lengthReady = true;
          break;
        }
        multiplier *= 128;
      }

      if (!lengthReady) {
        break;
      }

      const packetEnd = pos + remainingLen;
      if (packetEnd > merged.length) {
        break;
      }

      this.handlePacket(merged.slice(offset, packetEnd));
      offset = packetEnd;
    }

    this.pendingBuffer = merged.slice(offset);
  }

  private handlePacket(data: Uint8Array): void {
    if (data.length < 2) {
      return;
    }

    const packetType = data[0] & 0xF0;
    let pos = 1;
    let remainingLen = 0;
    let multiplier = 1;

    while (pos < data.length) {
      const encodedByte = data[pos++];
      remainingLen += (encodedByte & 0x7F) * multiplier;
      if ((encodedByte & 0x80) === 0) {
        break;
      }
      multiplier *= 128;
    }

    if (packetType === MQTT_CONNACK) {
      this.handleConnack(data, pos);
      return;
    }
    if (packetType === MQTT_SUBACK) {
      this.handleSuback(data, pos, remainingLen);
      return;
    }
    if (packetType === MQTT_PINGRESP) {
      return;
    }

    if (packetType === MQTT_PUBLISH && pos + 2 <= data.length) {
      const topicLength = (data[pos] << 8) | data[pos + 1];
      pos += 2;
      const topic = this.bytesToString(data, pos, topicLength);
      pos += topicLength;
      const payloadLength = remainingLen - 2 - topicLength;
      const payload = this.bytesToString(data, pos, payloadLength);
      this.emitStatus('Received ' + topic);

      if (this.messageCallback !== null) {
        this.messageCallback(topic, payload);
      }
    }
  }

  private handleConnack(data: Uint8Array, pos: number): void {
    if (pos + 1 >= data.length) {
      this.rejectWaiter(this.connackWaiter, new Error('MQTT CONNACK packet incomplete'));
      this.connackWaiter = null;
      return;
    }

    const returnCode = data[pos + 1];
    if (returnCode === 0) {
      this.resolveWaiter(this.connackWaiter);
    } else {
      this.rejectWaiter(this.connackWaiter, new Error('MQTT CONNACK failed: ' + returnCode.toString()));
    }
    this.connackWaiter = null;
  }

  private handleSuback(data: Uint8Array, pos: number, remainingLen: number): void {
    const qosPos = pos + remainingLen - 1;
    if (qosPos >= data.length) {
      this.rejectWaiter(this.subackWaiter, new Error('MQTT SUBACK packet incomplete'));
      this.subackWaiter = null;
      return;
    }

    const grantedQos = data[qosPos];
    if (grantedQos !== 0x80) {
      this.resolveWaiter(this.subackWaiter);
    } else {
      this.rejectWaiter(this.subackWaiter, new Error('MQTT subscription rejected'));
    }
    this.subackWaiter = null;
  }

  private waitForConnack(): Promise<void> {
    this.connackWaiter = this.createWaiter('MQTT CONNACK timeout');
    return new Promise<void>((resolve, reject) => {
      if (this.connackWaiter !== null) {
        this.connackWaiter.resolve = resolve;
        this.connackWaiter.reject = reject;
      }
    });
  }

  private waitForSuback(): Promise<void> {
    this.subackWaiter = this.createWaiter('MQTT SUBACK timeout');
    return new Promise<void>((resolve, reject) => {
      if (this.subackWaiter !== null) {
        this.subackWaiter.resolve = resolve;
        this.subackWaiter.reject = reject;
      }
    });
  }

  private createWaiter(timeoutMessage: string): PendingWaiter {
    const waiter = new PendingWaiter();
    waiter.timer = setTimeout(() => {
      waiter.reject(new Error(timeoutMessage));
    }, MQTT_WAIT_TIMEOUT_MS);
    return waiter;
  }

  private resolveWaiter(waiter: PendingWaiter | null): void {
    if (waiter === null) {
      return;
    }
    this.clearWaiter(waiter);
    waiter.resolve();
  }

  private rejectWaiter(waiter: PendingWaiter | null, error: Error): void {
    if (waiter === null) {
      return;
    }
    this.clearWaiter(waiter);
    waiter.reject(error);
  }

  private clearWaiter(waiter: PendingWaiter | null): void {
    if (waiter !== null && waiter.timer >= 0) {
      clearTimeout(waiter.timer);
      waiter.timer = -1;
    }
  }

  private bytesToString(data: Uint8Array, start: number, length: number): string {
    let text = '';
    for (let index = 0; index < length && start + index < data.length; index++) {
      text += String.fromCharCode(data[start + index]);
    }
    return text;
  }

  private nextPacketId(): number {
    this.packetId++;
    if (this.packetId > 65535) {
      this.packetId = 1;
    }
    return this.packetId;
  }

  private async resolveHostAddresses(): Promise<string[]> {
    if (this.isIpv4Literal(this.config.host)) {
      return [this.config.host];
    }

    this.emitStatus('DNS resolving ' + this.config.host);
    let results: connection.NetAddress[] = [];
    try {
      results = await connection.getAddressesByName(this.config.host);
    } catch (error) {
      throw new Error('DNS failed: ' + this.errorToText(error));
    }
    const addresses: string[] = [];

    for (let index = 0; index < results.length; index++) {
      const item = results[index];
      if (item.address.length > 0 && this.isIpv4Literal(item.address)) {
        addresses.push(item.address);
      }
    }

    if (addresses.length === 0) {
      throw new Error('DNS returned no IPv4 address for ' + this.config.host);
    }

    this.emitStatus('DNS resolved ' + this.config.host + ' -> ' + addresses[0]);
    return addresses;
  }

  private isIpv4Literal(value: string): boolean {
    const parts = value.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (let index = 0; index < parts.length; index++) {
      const num = Number(parts[index]);
      if (!Number.isInteger(num) || num < 0 || num > 255) {
        return false;
      }
    }
    return true;
  }

  private emitStatus(message: string): void {
    if (this.statusCallback !== null) {
      this.statusCallback(message);
    }
  }

  private errorToText(error: Object): string {
    try {
      return JSON.stringify(error);
    } catch (jsonError) {
      return String(error);
    }
  }
}
