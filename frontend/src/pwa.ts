import { useEffect, useState } from 'react'

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

/** WeChat's in-app browser (X5 kernel) blocks Web Share API and PWA install. */
export function isWeChat(): boolean {
  return /micromessenger/i.test(navigator.userAgent)
}

/** iOS Safari has no `beforeinstallprompt`; add-to-home-screen is manual. */
export function isIos(): boolean {
  return /iphone|ipad|ipod/i.test(navigator.userAgent)
}

function isStandalone(): boolean {
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    // iOS Safari
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  )
}

/**
 * Tracks the deferred `beforeinstallprompt` event so we can show an in-app
 * "add to home screen" button. On browsers without the prompt (iOS Safari),
 * `prompt` is null and the caller should fall back to manual instructions.
 */
export function useInstallPrompt() {
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null)
  const [installed, setInstalled] = useState(isStandalone())

  useEffect(() => {
    function onBeforeInstall(e: Event) {
      e.preventDefault()
      setDeferred(e as BeforeInstallPromptEvent)
    }
    function onInstalled() {
      setInstalled(true)
      setDeferred(null)
    }
    window.addEventListener('beforeinstallprompt', onBeforeInstall)
    window.addEventListener('appinstalled', onInstalled)
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstall)
      window.removeEventListener('appinstalled', onInstalled)
    }
  }, [])

  async function promptInstall(): Promise<'accepted' | 'dismissed' | 'unavailable'> {
    if (!deferred) return 'unavailable'
    await deferred.prompt()
    const choice = await deferred.userChoice
    if (choice.outcome === 'accepted') setInstalled(true)
    setDeferred(null)
    return choice.outcome
  }

  return { canInstall: !!deferred, installed, promptInstall }
}

export interface ShareResult {
  status: 'shared' | 'copied' | 'unavailable' | 'wechat'
}

/**
 * Opens the native share sheet; falls back to copying the link to clipboard.
 * In WeChat both are unavailable, so the caller should show the in-app guide.
 */
export async function shareApp(data?: { title?: string; text?: string; url?: string }): Promise<ShareResult> {
  if (isWeChat()) return { status: 'wechat' }
  const payload = {
    title: data?.title ?? document.title,
    text: data?.text ?? '河北科技大学影视学院录音系 · 录音实验室预约',
    url: data?.url ?? window.location.href,
  }
  if (navigator.share) {
    try {
      await navigator.share(payload)
      return { status: 'shared' }
    } catch {
      return { status: 'unavailable' }
    }
  }
  try {
    await navigator.clipboard.writeText(payload.url)
    return { status: 'copied' }
  } catch {
    return { status: 'unavailable' }
  }
}
