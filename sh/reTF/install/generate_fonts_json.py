import os
import json

def get_font_family_simple(file_name):
    # 去掉扩展名，移除空格，直接作为family名称
    stem = os.path.splitext(file_name)[0]
    return stem.replace(" ", "")

def scan_fonts(root_dir="."):
    result = []
    dir_map = {
        "en": "英-其他 ·",
        "zh": "中-其他 ·"
    }
    # 只扫描ttf，和你示例一致
    font_exts = (".ttf",)

    for dir_tag, name_prefix in dir_map.items():
        target_dir = os.path.join(root_dir, dir_tag)
        if not os.path.isdir(target_dir):
            print(f"文件夹不存在: {target_dir}")
            continue

        for dirpath, _, filenames in os.walk(target_dir):
            for fname in filenames:
                if fname.lower().endswith(font_exts):
                    full_path = os.path.join(dirpath, fname)
                    rel_src = os.path.relpath(full_path, root_dir).replace("\\", "/")
                    family_name = get_font_family_simple(fname)
                    file_stem = os.path.splitext(fname)[0]
                    display_name = f"{name_prefix} {file_stem}"

                    item = {
                        "name": display_name,
                        "family": f"'{family_name}', serif",
                        "src": f"./{rel_src}",
                        "type": "custom"
                    }
                    result.append(item)
    return result

if __name__ == "__main__":
    font_data = scan_fonts()
    output_json = {"fonts": font_data}
    with open("font.json", "w", encoding="utf-8") as f:
        json.dump(output_json, f, ensure_ascii=False, indent=2)
    print("已生成 font.json")
