import { describe, expect, it, beforeEach } from 'bun:test';
import React from 'react';
import { buttonVariants } from '../components/ui/button';
import { badgeVariants } from '../components/ui/badge';

describe('Design System Primitives', () => {
  describe('buttonVariants', () => {
    it('generates default variant with primary foreground', () => {
      const classes = buttonVariants({ variant: 'default' });
      expect(classes).toContain('bg-primary');
      expect(classes).toContain('text-primary-foreground');
    });

    it('generates destructive variant classes', () => {
      const classes = buttonVariants({ variant: 'destructive' });
      expect(classes).toContain('bg-status-destructive');
    });

    it('generates small size classes', () => {
      const classes = buttonVariants({ size: 'sm' });
      expect(classes).toContain('h-8');
      expect(classes).toContain('px-3');
    });
  });

  describe('badgeVariants', () => {
    it('generates default badge with alpha tints', () => {
      const classes = badgeVariants({ variant: 'default' });
      expect(classes).toContain('bg-primary/10');
      expect(classes).toContain('border-primary/30');
    });

    it('generates success badge classes', () => {
      const classes = badgeVariants({ variant: 'success' });
      expect(classes).toContain('bg-status-success/15');
    });
  });

  describe('Theme switching on document', () => {
    beforeEach(() => {
      document.documentElement.removeAttribute('data-theme');
      document.documentElement.removeAttribute('data-accent');
    });

    it('sets data-theme attribute on documentElement', () => {
      document.documentElement.setAttribute('data-theme', 'oled');
      expect(document.documentElement.getAttribute('data-theme')).toBe('oled');

      document.documentElement.setAttribute('data-theme', 'dim');
      expect(document.documentElement.getAttribute('data-theme')).toBe('dim');

      document.documentElement.setAttribute('data-theme', 'light');
      expect(document.documentElement.getAttribute('data-theme')).toBe('light');
    });

    it('sets data-accent attribute on documentElement', () => {
      document.documentElement.setAttribute('data-accent', 'emerald');
      expect(document.documentElement.getAttribute('data-accent')).toBe('emerald');

      document.documentElement.setAttribute('data-accent', 'indigo');
      expect(document.documentElement.getAttribute('data-accent')).toBe('indigo');
    });
  });
});
