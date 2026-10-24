import { GlobalWindow } from 'happy-dom';

const window = new GlobalWindow();
(globalThis as unknown as { window: unknown }).window = window;
(globalThis as unknown as { document: unknown }).document = window.document;
(globalThis as unknown as { HTMLElement: unknown }).HTMLElement = window.HTMLElement;
