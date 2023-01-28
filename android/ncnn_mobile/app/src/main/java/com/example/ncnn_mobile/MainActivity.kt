package com.example.ncnn_mobile

import android.Manifest
import android.R.attr
import android.content.pm.PackageManager
import android.graphics.*
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.Size
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.*
import androidx.camera.video.VideoCapture
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.ncnn_mobile.databinding.ActivityMainBinding
import com.tencent.yolov5ncnn.YoloV5Ncnn
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors


typealias Yolov5NcnnListener = (objects: Array<YoloV5Ncnn.Obj>?, bitmap: Bitmap?) -> Unit


class MainActivity : AppCompatActivity() {
    private lateinit var viewBinding: ActivityMainBinding

    private var imageCapture: ImageCapture? = null

    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null

    private lateinit var cameraExecutor: ExecutorService

    private var yolov5ncnn = YoloV5Ncnn()

    private class Yolov5NcnnAnalyzer(private val yolov5ncnn: YoloV5Ncnn, private val listener: Yolov5NcnnListener) : ImageAnalysis.Analyzer {
        override fun analyze(image: ImageProxy) {
            val bitmap = imageToBitmap(image, 0f)
            Log.d(TAG, "${bitmap?.width}, ${bitmap?.height}")
            var objects: Array<YoloV5Ncnn.Obj>? = yolov5ncnn.Detect(bitmap, true)
            if (objects == null) {
                objects = yolov5ncnn.Detect(bitmap, false)
            }

            listener(objects, bitmap)

            image.close()
        }

        // ImageProxy → Bitmap
        private fun imageToBitmap(image: ImageProxy, rotationDegrees: Float): Bitmap? {
            val data = imageToByteArray(image)
            val bitmap = BitmapFactory.decodeByteArray(data, 0, data!!.size)
            return if (rotationDegrees == 0.0f) {
                bitmap
            } else {
                rotateBitmap(bitmap, rotationDegrees)
            }
        }

        // Bitmapの回転
        private fun rotateBitmap(bitmap: Bitmap, rotationDegrees: Float): Bitmap? {
            val mat = Matrix()
            mat.postRotate(rotationDegrees)
            return Bitmap.createBitmap(
                bitmap, 0, 0,
                bitmap.width, bitmap.height, mat, true
            )
        }

        // Image → JPEGのバイト配列
        private fun imageToByteArray(image: ImageProxy): ByteArray? {
            var data: ByteArray? = null
            Log.i(TAG, "image.format: ${image.format}")
            if (image.format === ImageFormat.JPEG) {
                val planes: Array<out ImageProxy.PlaneProxy> = image.planes
                val buffer: ByteBuffer = planes[0].buffer
                data = ByteArray(buffer.capacity())
                buffer[data]
                return data
            } else if (image.format === ImageFormat.YUV_420_888) {
                data = NV21toJPEG(
                    YUV_420_888toNV21(image),
                    image.width, image.height
                )
            }
            return data
        }

        // YUV_420_888 → NV21
        private fun YUV_420_888toNV21(image: ImageProxy): ByteArray {
            val nv21: ByteArray
            val yBuffer: ByteBuffer = image.planes.get(0).buffer
            val uBuffer: ByteBuffer = image.planes.get(1).buffer
            val vBuffer: ByteBuffer = image.planes.get(2).buffer
            val ySize = yBuffer.remaining()
            val uSize = uBuffer.remaining()
            val vSize = vBuffer.remaining()
            nv21 = ByteArray(ySize + uSize + vSize)
            yBuffer[nv21, 0, ySize]
            vBuffer[nv21, ySize, vSize]
            uBuffer[nv21, ySize + vSize, uSize]
            return nv21
        }

        // NV21 → JPEG
        private fun NV21toJPEG(nv21: ByteArray, width: Int, height: Int): ByteArray? {
            val out = ByteArrayOutputStream()
            val yuv = YuvImage(nv21, ImageFormat.NV21, width, height, null)
            yuv.compressToJpeg(Rect(0, 0, width, height), 100, out)
            return out.toByteArray()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        viewBinding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(viewBinding.root)

        yolov5ncnn.Init(assets)

        // Request camera permissions
        if (allPermissionsGranted()) {
            startCamera()
        } else {
            ActivityCompat.requestPermissions(
                this, REQUIRED_PERMISSIONS, REQUEST_CODE_PERMISSIONS)
        }

        cameraExecutor = Executors.newSingleThreadExecutor()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults:
        IntArray) {
        if (requestCode == REQUEST_CODE_PERMISSIONS) {
            if (allPermissionsGranted()) {
                startCamera()
            } else {
                Toast.makeText(this,
                    "Permissions not granted by the user.",
                    Toast.LENGTH_SHORT).show()
                finish()
            }
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            // Used to bind the lifecycle of cameras to the lifecycle owner
            val cameraProvider: ProcessCameraProvider = cameraProviderFuture.get()

            // Preview
            val preview = Preview.Builder()
                .build()
                .also {
                    it.setSurfaceProvider(viewBinding.viewFinder.surfaceProvider)
                }
            imageCapture = ImageCapture.Builder().build()
            val imageAnalyzer = ImageAnalysis.Builder()
                .setTargetResolution(Size(640, 640))
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor, Yolov5NcnnAnalyzer(yolov5ncnn) { objects: Array<YoloV5Ncnn.Obj>?, bitmap: Bitmap? ->
                        showObjects(
                            objects,
                            bitmap
                        )
                    })
                }
            // Select back camera as a default
            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                // Unbind use cases before rebinding
                cameraProvider.unbindAll()

                // Bind use cases to camera
                cameraProvider.bindToLifecycle(
                    this, cameraSelector, preview, imageCapture, imageAnalyzer)

            } catch(exc: Exception) {
                Log.e(TAG, "Use case binding failed", exc)
            }

        }, ContextCompat.getMainExecutor(this))
    }

    private fun showObjects(objects: Array<YoloV5Ncnn.Obj>?, bitmap: Bitmap?) {
        if (objects == null || bitmap == null) {
            //viewBinding.imageView.setImageBitmap(bitmap)
            return
        }

        // draw objects on bitmap
        val rgba: Bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val colors = intArrayOf(
            Color.rgb(54, 67, 244),
            Color.rgb(99, 30, 233),
            Color.rgb(176, 39, 156),
            Color.rgb(183, 58, 103),
            Color.rgb(181, 81, 63),
            Color.rgb(243, 150, 33),
            Color.rgb(244, 169, 3),
            Color.rgb(212, 188, 0),
            Color.rgb(136, 150, 0),
            Color.rgb(80, 175, 76),
            Color.rgb(74, 195, 139),
            Color.rgb(57, 220, 205),
            Color.rgb(59, 235, 255),
            Color.rgb(7, 193, 255),
            Color.rgb(0, 152, 255),
            Color.rgb(34, 87, 255),
            Color.rgb(72, 85, 121),
            Color.rgb(158, 158, 158),
            Color.rgb(139, 125, 96)
        )
        val canvas = Canvas(rgba)
        val paint = Paint()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 4f
        val textbgpaint = Paint()
        textbgpaint.color = Color.WHITE
        textbgpaint.style = Paint.Style.FILL
        val textpaint = Paint()
        textpaint.color = Color.BLACK
        textpaint.textSize = 26f
        textpaint.textAlign = Paint.Align.LEFT
        for (i in objects.indices) {
            paint.color = colors[i % 19]
            canvas.drawRect(
                objects[i].x,
                objects[i].y,
                objects[i].x + objects[i].w,
                objects[i].y + objects[i].h,
                paint
            )

            // draw filled text inside image
            run {
                val text = objects[i].label + " = " + String.format(
                    "%.1f",
                    objects[i].prob * 100
                ) + "%"
                val text_width = textpaint.measureText(text)
                val text_height = -textpaint.ascent() + textpaint.descent()
                var x = objects[i].x
                var y = objects[i].y - text_height
                if (y < 0) y = 0f
                if (x + text_width > rgba.width) x = rgba.width - text_width
                canvas.drawRect(x, y, x + text_width, y + text_height, textbgpaint)
                canvas.drawText(text, x, y - textpaint.ascent(), textpaint)
            }
        }
        runOnUiThread { viewBinding.imageView.setImageBitmap(rgba) }
        //viewBinding.imageView.setImageBitmap(rgba)
    }

    private fun allPermissionsGranted() = REQUIRED_PERMISSIONS.all {
        ContextCompat.checkSelfPermission(
            baseContext, it) == PackageManager.PERMISSION_GRANTED
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
    }

    companion object {
        private const val TAG = "ncnn_mobile"
        private const val FILENAME_FORMAT = "yyyy-MM-dd-HH-mm-ss-SSS"
        private const val REQUEST_CODE_PERMISSIONS = 10
        private val REQUIRED_PERMISSIONS =
            mutableListOf (
                Manifest.permission.CAMERA,
                Manifest.permission.RECORD_AUDIO
            ).apply {
                if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                    add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                }
            }.toTypedArray()
    }
}
