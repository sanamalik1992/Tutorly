import redis from '../../lib/redis.js'
import { handleCors, requireAuth } from '../../lib/cors.js'
import { setUserPro } from '../../lib/user.js'

const PRO_PRODUCTS = new Set(['com.tutorly.pro.monthly', 'com.tutorly.pro.annual'])

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' })

  const payload = await requireAuth(req, res)
  if (!payload) return

  try {
    const userId = payload.sub
    const { productID, transactionID, originalTransactionID, purchaseDate, environment = 'Production' } = req.body ?? {}

    if (!productID || !transactionID) {
      return res.status(400).json({ error: 'productID and transactionID required' })
    }
    if (!PRO_PRODUCTS.has(productID)) {
      return res.status(400).json({ error: `Unknown product: ${productID}` })
    }

    // Persist transaction record (iap:{txnId} → JSON)
    const iapKey = `iap:${transactionID}`
    const existing = await redis.get(iapKey)
    if (!existing) {
      await redis.set(iapKey, JSON.stringify({
        transactionID,
        originalTransactionID: originalTransactionID ?? transactionID,
        userId,
        productID,
        purchaseDate:  purchaseDate ?? new Date().toISOString(),
        environment,
        verifiedAt:    new Date().toISOString(),
      }))
    }

    // Grant Pro — idempotent
    await setUserPro(userId)

    console.log(`[iap/verify] Pro granted — user=${userId} product=${productID} txn=${transactionID} env=${environment}`)
    return res.json({ ok: true, isPro: true })
  } catch (err) {
    console.error('[iap/verify]', err)
    return res.status(500).json({ error: 'Failed to verify purchase' })
  }
}
