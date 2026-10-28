把备用桌面图标（PNG，正方形，192–4096 像素，建议 512×512）放入此文件夹。
文件名即设置页面显示的名称，例如：高气压.png、春风拂面.png。
文件名前的数字只用于排序，例如 2.高气压.png 在应用内显示为「高气压」。
默认图标使用 assets/icon.png（微风与低音），关于页使用 assets/about.png，两者都不放入此目录。
项目根目录运行：python tool/generate_launcher_variants.py
修改默认图标后还需运行：python tool/generate_icons.py（Android 各密度 mipmap 与 Windows 图标）
生成后重新编译并安装 Android 应用。不要在应用运行时才复制 PNG：图标必须预先打包。
