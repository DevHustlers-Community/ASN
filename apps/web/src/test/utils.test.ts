import { describe, expect, it } from 'bun:test';
import { cn } from '../lib/utils';

describe('cn utility', () => {
  it('merges class names correctly', () => {
    expect(cn('px-2', 'py-1')).toBe('px-2 py-1');
  });

  it('resolves conflicting tailwind classes', () => {
    expect(cn('px-2', 'px-4')).toBe('px-4');
  });

  it('handles conditional falsy values', () => {
    expect(cn('base', false && 'hidden', undefined, null, 'active')).toBe('base active');
  });
});
