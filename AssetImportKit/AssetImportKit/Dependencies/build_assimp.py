import os
from subprocess import call

assimp_dir = "./assimpLib/"
build_file = os.path.join(assimp_dir, "port/iOS/build.sh")
build_temp_file = os.path.join(assimp_dir, "port/iOS/build_current.sh")
build_folder = os.path.join(assimp_dir, "lib/iOS/")

arch_flag_name_device = "BUILD_ARCHS_DEVICE"
arch_flag_name_simulator = "BUILD_ARCHS_SIMULATOR"

valid_archs_device = "arm64e arm64"
valid_archs_simulator = "x86_64"

origin_build_file = open(build_file)
lines = origin_build_file
new_lines = []
new_file = open(build_temp_file, 'w')


def check_line_from_parts(left, right):
    if line.startswith(left):
        return left + '="' + right + '"\n'
    return line


for line in lines:
    line = check_line_from_parts(arch_flag_name_device, valid_archs_device)
    line = check_line_from_parts(arch_flag_name_simulator, valid_archs_simulator)
    new_lines.append(line)
# print(new_lines)
new_file.writelines(new_lines)
new_file.close()
origin_build_file.close()
os.chdir(os.path.dirname(build_temp_file))
build_temp_file = os.path.basename(build_temp_file)
call(["sh", build_temp_file])
os.remove(build_temp_file)
