把你设计的备用桌面图标（PNG，正方形，192–4096 像素）放入此文件夹。
文件名即设置页面的显示名称，例如：经典蓝.png、极简黑.png。
项目根目录运行：python tool/generate_launcher_variants.py
然后重新编译并安装 Android 应用。不要在应用运行时才复制 PNG：图标必须预先打包。
默认图标继续使用 assets/icon.png，无需复制到这里。
