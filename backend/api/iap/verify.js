import supabase from '../../lib/supabase.js'
import { handleCors, requireAuth } from '../../lib/cors.js'

const PRO_PRODUCTS = new Set(['com.tutorly.pro.monthly', 'com.tutorly.pro.annual'])

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' })

  const payload = await requireAuth(req, res)
  if (!payload) return

  try {
    const userId = payload.sub
    const {
      productID,
      transactionID,
      originalTransactionID,
      purchaseDate,
      environment = 'Production',
    } = req.body

    if (!productID || !transactionID) {
      return res.status(400).json({ error: 'productID and transactionID required' })
    }

    if (!PRO_PRODUCTS.has(productID)) {
      return res.status(400).json({ error: `Unknown product: ${productID}` })
    }

    // Persist transaction (ignore duplicate submissions)
    const { error: txnErr } = await supabase.from('tutorly_iap').upsert(
      {
        transaction_id:          transactionID,
        original_transaction_id: originalTransactionID ?? transactionID,
        user_id:                 userId,
        product_id:              productID,
        purchase_date:           purchaseDate ? new Date(purchaseDate).toISOString() : new Date().toISOString(),
        environment,
      },
      { onConflict: 'transaction_id' }
    )
    if (txnErr) throw txnErr

    // Grant Pro status
    const { error: userErr } = await supabase
      .from('tutorly_users')
      .update({ is_pro: true })
      .eq('id', userId)
    if (userErr) throw userErr

    console.log(`[iap/verify] Pro granted — user=${userId} product=${productID} txn=${transactionID} env=${environment}`)
    return res.json({ ok: true, isPro: true })
  } catch (err) {
    console.error('[iap/verify]', err)
    return res.status(500).json({ error: 'Failed to verify purchase' })
  }
}
