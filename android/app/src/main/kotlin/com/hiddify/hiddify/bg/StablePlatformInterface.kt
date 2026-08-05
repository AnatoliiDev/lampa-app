package com.hiddify.hiddify.bg

import android.util.Log
import com.hiddify.core.libbox.Notification
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.TunOptions
import go.Seq

/**
 * Незмінний об'єкт, який ядро бачить як свій PlatformInterface, і який лише
 * передає виклики нинішній службі.
 *
 * Навіщо. `Mobile.setup` віддає ядру Java-об'єкт, і gomobile заводить на нього
 * запис у своїй таблиці посилань. Ядро запам'ятовує його назавжди: у
 * `hiddify-core` (v2/hcore/grpc_server.go) повторний `Setup` для того самого
 * режиму виходить одразу, не оновлюючи збережений інтерфейс. Тим часом кожен
 * запуск служби створює **новий** екземпляр VPNService і передає в `Setup`
 * саме його. Старий запис у таблиці посилань стає непотрібним, gomobile його
 * прибирає — а ядро й далі кличе по ньому. Наслідок:
 *
 *     go/Seq  : Unknown reference: 42
 *     Fatal signal 6 (SIGABRT) … go_seq_from_refnum
 *
 * Це не виняток Dart, а обвал усього процесу, тож у звітах із телефона його не
 * видно. Відтворюється надійно: перше підключення після перезапуску служби
 * тримається, а наступне валить застосунок за десяті частки секунди.
 *
 * Ліки. Ядру віддаємо цей об'єкт — він один на процес і живе, доки живе процес,
 * тож його запис у таблиці посилань не зникає ніколи. Служби ж підмінюються під
 * ним: `bind` на старті, `unbind` на зупинці.
 *
 * Заразом лікується друга біда того самого кореня: після перезапуску ядро
 * зверталося до вже знищеного екземпляра служби, бо оновити збережений
 * інтерфейс воно не вміє.
 */
object StablePlatformInterface : PlatformInterfaceWrapper {
    @Volatile
    private var delegate: PlatformInterface? = null

    private val pinned = java.util.concurrent.atomic.AtomicBoolean(false)

    /**
     * Додає в таблицю посилань gomobile одну одиницю, яку ніхто ніколи не зніме.
     *
     * Кожен виклик із ядра в Java працює за схемою «збільшити лічильник — узяти
     * об'єкт — зменшити лічильник» (див. go_seq_from_refnum у seq_android.c).
     * Десь у цій парі лічильник розходиться: він доходить до нуля, запис із
     * таблиці зникає, і наступний виклик валить процес сигналом SIGABRT —
     * «go/Seq: Unknown reference: 42». Це перегони, а не проста помилка: варто
     * було додати в ядро докладне журналювання, яке сповільнює ці виклики, і
     * падіння зникало.
     *
     * Шукати того, хто віднімає зайве, всередині готового .aar можна довго.
     * Натомість тримаємо власну одиницю: сума ніколи не дійде до нуля, запис
     * живе, доки живе процес. Ціна — один об'єкт, який не звільниться, і він
     * однаково потрібен весь час роботи застосунку.
     *
     * `Seq.decRef` доступний лише всередині пакета `go`, тож зняти цю одиницю
     * ззовні неможливо навіть випадково.
     */
    fun pinForever() {
        if (pinned.compareAndSet(false, true)) {
            val refnum = Seq.incRef(this)
            Log.d("A/StablePlatform", "закріплено в таблиці посилань: $refnum")
        }
    }

    fun bind(target: PlatformInterface) {
        delegate = target
    }

    fun unbind(target: PlatformInterface) {
        if (delegate === target) delegate = null
    }

    /**
     * Коли служби немає, кидаємо звичайний виняток: gomobile перетворить його на
     * помилку Go, і ядро її обробить. Раніше на цьому місці процес просто гинув.
     */
    private fun current(): PlatformInterface = delegate ?: error("android: служба не запущена")

    override fun openTun(options: TunOptions): Int = current().openTun(options)

    override fun autoDetectInterfaceControl(fd: Int) = current().autoDetectInterfaceControl(fd)

    override fun sendNotification(notification: Notification) = current().sendNotification(notification)
}
