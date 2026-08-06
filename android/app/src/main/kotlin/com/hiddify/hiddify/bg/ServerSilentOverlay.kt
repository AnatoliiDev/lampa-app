package com.hiddify.hiddify.bg

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings as AndroidSettings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.hiddify.hiddify.constant.Action

/**
 * Вікно «сервер не відповідає» поверх усіх застосунків.
 *
 * Сповіщення для цього не годиться: воно за задумом системи живе у шторці, а
 * людина в цей час дивиться відео й туди не заглядає. Тунель при цьому мовчки
 * забирає в неї інтернет, і причина лишається невидимою.
 *
 * Вимагає дозволу «показувати поверх інших вікон». Його видають вручну, тож
 * коли дозволу немає — мовчки відступаємо, і людина побачить те саме
 * сповіщення. Це навмисно: краще тихіше повідомлення, ніж жодного.
 */
object ServerSilentOverlay {
    private const val TAG = "A/Overlay"

    private var view: View? = null

    fun canShow(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || AndroidSettings.canDrawOverlays(context)

    /** Головний потік обов'язковий: вікна малює тільки він. */
    fun show(context: Context) {
        if (view != null || !canShow(context)) return
        val manager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val dp = { value: Int ->
            TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                value.toFloat(),
                context.resources.displayMetrics,
            ).toInt()
        }

        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(16))
            background = GradientDrawable().apply {
                cornerRadius = dp(20).toFloat()
                setColor(Color.WHITE)
            }
            addView(
                TextView(context).apply {
                    text = "Сервер VPN (Лампа) не отвечает"
                    setTextColor(Color.parseColor("#B3261E"))
                    textSize = 17f
                    setTypeface(typeface, android.graphics.Typeface.BOLD)
                },
            )
            addView(
                TextView(context).apply {
                    text = "Интернет через него не пойдёт. Отключитесь и попробуйте позже."
                    setTextColor(Color.parseColor("#44464F"))
                    textSize = 14f
                    setPadding(0, dp(8), 0, dp(16))
                },
            )
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.END
                    addView(
                        Button(context).apply {
                            text = "Позже"
                            setOnClickListener { hide(context) }
                        },
                    )
                    addView(
                        Button(context).apply {
                            text = "Отключить"
                            setOnClickListener {
                                context.sendBroadcast(
                                    Intent(Action.SERVICE_CLOSE).setPackage(context.packageName),
                                )
                                hide(context)
                            }
                        },
                    )
                },
            )
        }

        val root = LinearLayout(context).apply {
            gravity = Gravity.CENTER
            setPadding(dp(20), 0, dp(20), 0)
            setBackgroundColor(Color.parseColor("#99000000"))
            addView(card, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            // Вікно ловить дотики саме на собі, решту екрана не чіпає, але й не
            // пропускає крізь себе: інакше людина тицяла б у відео повз нього.
            0,
            android.graphics.PixelFormat.TRANSLUCENT,
        )

        runCatching { manager.addView(root, params) }
            .onSuccess {
                view = root
                Log.d(TAG, "показано вікно поверх інших")
            }
            .onFailure { Log.w(TAG, "не вдалося показати вікно: ${it.message}") }
    }

    fun hide(context: Context) {
        val current = view ?: return
        view = null
        val manager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        runCatching { manager.removeView(current) }
    }
}
