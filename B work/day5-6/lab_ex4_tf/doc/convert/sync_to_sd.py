import os
import sys
import glob
import shutil
import argparse

def corrupt_old_bmp_headers(target_drive):
    """
    遍历目标驱动器下的所有 .bmp 文件，将其开头的 'BM' 魔数修改为 'XX'。
    这样 FPGA 的物理扇区扫描就不会把这些“被标记为删除但物理数据还在”的文件识别为有效图片。
    """
    print(f"正在扫描 {target_drive} 驱动器，准备清除旧图片的 BMP 识别头...")
    
    # 查找根目录下的所有 bmp 文件（你也可以用 os.walk 查找所有子目录）
    search_pattern = os.path.join(target_drive, "*.bmp")
    bmp_files = glob.glob(search_pattern)
    
    corrupt_count = 0
    for bmp_file in bmp_files:
        try:
            # 以读写模式打开文件（不截断）
            with open(bmp_file, 'r+b') as f:
                header = f.read(2)
                if header == b'BM':
                    # 将指针移回开头
                    f.seek(0)
                    # 写入随意字符破坏魔数，例如 'XX'
                    f.write(b'XX')
                    corrupt_count += 1
                    print(f"  [清除有效] 已破坏头文件: {os.path.basename(bmp_file)}")
        except Exception as e:
            print(f"  [警告] 无法处理文件 {bmp_file}: {e}")
            
    print(f"头文件清除完毕，共处理了 {corrupt_count} 个旧图片文件。")

def clean_drive(target_drive):
    """
    删除目标驱动器下的所有文件，模拟格式化/清空操作（不删除隐藏系统文件夹）。
    """
    print(f"\n正在清空 {target_drive} 驱动器中的旧文件...")
    for item in os.listdir(target_drive):
        item_path = os.path.join(target_drive, item)
        # 跳过系统隐藏文件夹如 System Volume Information
        if item.startswith('.'):
            continue
            
        try:
            if os.path.isfile(item_path):
                os.remove(item_path)
            elif os.path.isdir(item_path):
                shutil.rmtree(item_path)
        except Exception as e:
            print(f"  [警告] 无法删除 {item_path}: {e}")
    print("驱动器清空完毕。")

def sync_new_images(source_dir, target_drive, max_count=4):
    """
    从源文件夹中挑选最多 max_count 张 BMP 图片，复制到目标驱动器。
    """
    if not os.path.exists(source_dir):
        print(f"\n[错误] 源文件夹不存在: {source_dir}")
        return

    bmp_files = glob.glob(os.path.join(source_dir, "*.bmp"))
    if not bmp_files:
        print(f"\n[错误] 源文件夹 {source_dir} 中没有找到任何 BMP 图片。")
        return

    # 按名称排序，保证顺序一致性
    bmp_files.sort()
    
    # 限制复制的数量
    files_to_copy = bmp_files[:max_count]
    
    print(f"\n准备将 {len(files_to_copy)} 张图片同步到 {target_drive}...")
    
    success_count = 0
    for i, bmp_file in enumerate(files_to_copy):
        try:
            filename = os.path.basename(bmp_file)
            # 为了让 FPGA 物理扇区尽量连续，我们在文件名前加上序号
            target_name = f"{i:02d}_{filename}"
            target_path = os.path.join(target_drive, target_name)
            
            shutil.copy2(bmp_file, target_path)
            print(f"  [同步成功] {filename} -> {target_name}")
            success_count += 1
        except Exception as e:
            print(f"  [同步失败] {filename}: {e}")
            
    print(f"\n同步完成！成功写入 {success_count} 张新图片。")
    print("你现在可以安全弹出 SD 卡，插入 FPGA 开发板了。")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FPGA SD卡 图片同步工具 (防物理残留死锁版)")
    parser.add_argument('drive', help='SD 卡所在的盘符 (例如: E: 或 E:\\)')
    parser.add_argument('-s', '--source', help='存放转换好 BMP 图片的源文件夹 (默认: 当前目录的 output_bmp)', default=None)
    parser.add_argument('-n', '--num', type=int, default=4, help='最多同步的图片数量 (默认: 4)')
    
    args = parser.parse_args()

    # 处理盘符格式，确保以路径分隔符结尾
    target_drive = args.drive
    if not target_drive.endswith(':\\') and not target_drive.endswith(':/'):
        if target_drive.endswith(':'):
            target_drive += '\\'
        else:
            target_drive += ':\\'

    if not os.path.exists(target_drive):
        print(f"[致命错误] 找不到指定的驱动器: {target_drive}")
        print("请检查 SD 卡是否已正确插入电脑并分配了盘符。")
        sys.exit(1)

    # 确定源文件夹
    current_dir = os.path.dirname(os.path.abspath(__name__))
    source_dir = args.source if args.source else os.path.join(current_dir, "output_bmp")

    print("="*50)
    print(f"目标 SD 卡盘符: {target_drive}")
    print(f"图片源文件夹  : {source_dir}")
    print("="*50)
    
    # 为了防止误操作清空 C 盘，做个简单拦截
    if target_drive.upper().startswith('C:'):
        confirm = input("警告: 你指定了系统盘(C:)！这可能会导致系统崩溃。你确定要继续吗？(y/N): ")
        if confirm.lower() != 'y':
            print("操作已取消。")
            sys.exit(0)

    # 步骤 1: 破坏旧 BMP 的物理文件头
    corrupt_old_bmp_headers(target_drive)
    
    # 步骤 2: 清空 SD 卡（从文件系统层面）
    clean_drive(target_drive)
    
    # 步骤 3: 复制新图片
    sync_new_images(source_dir, target_drive, max_count=args.num)
