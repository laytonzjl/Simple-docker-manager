#!binbash

# ==========================================
# 颜色与全局变量定义
# ==========================================
C_GREEN='033[92m'
C_RED='033[91m'
C_YELLOW='033[93m'
C_CYAN='033[96m'
C_RESET='033[0m'

BASE_IMAGE=pytorchpytorch2.5.1-cuda12.1-cudnn9-devel

# ==========================================
# 辅助函数
# ==========================================
print_header() {
    clear
    echo -e ${C_CYAN}====================================================${C_RESET}
    echo -e ${C_CYAN}                           实验室容器管理系统 ${C_RESET}
    echo -e ${C_CYAN}====================================================${C_RESET}n
}

pause() {
    echo -e n${C_GREEN}按回车键继续...${C_RESET}
    read -r
}

# ==========================================
# 功能 1 初始化宿主机
# ==========================================
init_host_env() {
    print_header
    echo -e ${C_YELLOW}正在初始化宿主机环境...${C_RESET}n

    apt update
    apt install -y docker.io curl
    systemctl enable docker
    systemctl start docker

    curl -fsSL httpsmirrors.ustc.edu.cnlibnvidia-containergpgkey  gpg --dearmor -o usrsharekeyringsnvidia-container-toolkit-keyring.gpg --yes
    curl -s -L httpsmirrors.ustc.edu.cnlibnvidia-containerstabledebnvidia-container-toolkit.list  
        sed 's#deb httpsnvidia.github.io#deb [signed-by=usrsharekeyringsnvidia-container-toolkit-keyring.gpg] httpsmirrors.ustc.edu.cn#g'  
        tee etcaptsources.list.dnvidia-container-toolkit.list

    apt-get update
    apt-get install -y nvidia-container-toolkit

    echo -e n配置 etcdockerdaemon.json (使用 cgroupfs)...
    mkdir -p etcdocker
    cat  etcdockerdaemon.json EOF
{
registry-mirrors [
   httpsdocker.m.daocloud.io,
   httpsdocker.imgdb.de,
   httpsdocker-0.unsee.tech,
   httpsdocker.hlmirror.com,
   httpscjie.eu.org
],
exec-opts [native.cgroupdriver=cgroupfs]
}
EOF

    systemctl daemon-reload
    systemctl restart docker

    echo -e n${C_GREEN}依赖安装完成！${C_RESET}
    pause
}

# ==========================================
# 功能 2 查看所有容器
# ==========================================
view_containers() {
    print_header
    docker ps -a --format table {{.Names}}t{{.Status}}t{{.Ports}}t{{.Image}}
    pause
}

# ==========================================
# 功能 3 单个容器管理
# ==========================================
manage_single() {
    print_header
    echo -e ${C_CYAN}当前系统中的容器列表：${C_RESET}
    docker ps -a --format {{.Names}}t({{.Status}})
    echo 

    read -p 请输入要操作的容器名称 (输入 0 返回)  c_name
    [[ -z $c_name  $c_name == 0 ]] && return

    echo -e n1. 启动n2. 停止n3. 删除n4. 进入容器 (exec -it bash)n5. 重启
    read -p $(echo -e ${C_YELLOW}请输入操作序号 ${C_RESET}) action

    case $action in
        1) docker start $c_name ;;
        2) docker stop $c_name ;;
        3) docker rm -f $c_name ;;
        4) docker exec -it $c_name binbash ;;
        5) 
            # 执行重启并在后台拉起 SSH 服务
            docker restart $c_name && docker exec $c_name service ssh start 
            ;;
    esac
    pause
}

# ==========================================
# 功能 4 批量创建 (保留 _ 截取逻辑)
# ==========================================
batch_create() {
    print_header
    echo -e ${C_YELLOW}--- 批量创建 ---${C_RESET}n

    # 自动运行 df -h 并过滤无用虚拟设备，方便核对 HDD 路径
    echo -e ${C_CYAN}[系统磁盘检测] 当前物理磁盘挂载情况如下${C_RESET}
    echo ----------------------------------------------------------------------
    df -h  grep -E FilesystemSize
    df -h  grep -vE tmpfsloopudevoverlay
    echo ----------------------------------------------------------------------
    echo 

    # 配置全局物理盘
    read -p 请输入基础盘挂载目录 (默认 hddraid10)  base_disk
    base_disk=${base_disk-hddraid10}

    # 自动读取选定基础盘下已经存在的子文件夹并打印输出
    echo -e ${C_CYAN}[提示] 基础盘 (${base_disk}) 下已有的父目录有${C_RESET}
    if [ -d $base_disk ]; then
        # 过滤出以斜杠结尾的文件夹名，并去掉斜杠本身
        local existing_dirs=$(ls -p $base_disk 2devnull  grep '$'  sed 's')
        if [ -z $existing_dirs ]; then
            echo -e   ${C_YELLOW}(该磁盘目录下目前没有任何子目录)${C_RESET}
        else
            # 将换行符替换为“、”号，合并在一行美观输出
            echo -e   ${C_GREEN}${existing_dirs$'n' 、 }${C_RESET}
        fi
    else
        echo -e   ${C_RED}(警告 选定的基础盘路径在宿主机中不存在，脚本稍后将自动尝试级联创建)${C_RESET}
    fi
    echo 

    # 配置多级父目录位置
    read -p 请输入更高一级的父目录 (如 stu2024edu2025，直接回车默认使用 edu)  parent_dir
    parent_dir=${parent_dir-edu}
    echo 

    read -p 你要一次性创建几个容器？(输入数字)  count
    # 正则校验输入是否为数字
    [[ ! $count =~ ^[0-9]+$ ]] && echo -e ${C_RED}输入无效${C_RESET} && pause && return

    read -p 统一设置这些容器的 root 密码 (例如 123456)  root_pwd

    # 定义数组用于临时存储批量配置
    local NAMES=()
    local GPUS=()
    local PORTS=()
    local DIRS=()

    # 第一阶段：交互收集数据
    for (( i=1; i=count; i++ )); do
        echo -e n${C_CYAN}[配置第 $i$count 个容器]${C_RESET}
        read -p 1. 容器名 (如 xxx_xgpu)  name
        read -p 2. 分配GPU (如 2,3)  gpu
        read -p 3. 映射SSH端口 (如 15002)  port

        # Bash 核心截取逻辑：截取最后一个 '_' 左边的所有字符
        base_name=${name%%_}
        
        # 智能拼接多级目录：基础盘父目录学生名
        default_dir=${base_disk}${parent_dir}${base_name}

        read -p 4. 宿主机挂载目录 (默认 $default_dir，直接回车即使用默认)  dir_path
        # 如果未输入，则使用默认值
        dir_path=${dir_path-$default_dir}

        NAMES+=($name)
        GPUS+=($gpu)
        PORTS+=($port)
        DIRS+=($dir_path)
    done

    # 第二阶段：根据收集的数据自动建置
    for (( i=0; icount; i++ )); do
        local c_name=${NAMES[$i]}
        local c_gpu=${GPUS[$i]}
        local c_port=${PORTS[$i]}
        local c_dir=${DIRS[$i]}

        echo -e n----------------------------------------
        echo 正在部署容器 $c_name 

        mkdir -p $c_dir

        echo [$c_name] 步骤1 启动底层容器...
        docker run -it -d 
            --name $c_name 
            --restart=always 
            --gpus device=$c_gpu 
            --shm-size=16g 
            -p $c_port22 
            -v $c_dirworkspace 
            -v etcaptsources.listetcaptsources.list 
            $BASE_IMAGE

        if [ $ -ne 0 ]; then
            echo -e ${C_RED}容器启动失败，请检查端口是否被占用，跳过后续步骤。${C_RESET}
            continue
        fi

        echo [$c_name] 步骤2 正在容器内安装依赖...
        docker exec $c_name bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server sudo vim'

        echo [$c_name] 步骤3 修改配置...
        docker exec $c_name sed -i 
            -e s^[#]PermitRootLogin.PermitRootLogin yes 
            -e s^[#]PasswordAuthentication.PasswordAuthentication yes 
            -e s^UsePAM.UsePAM no 
            etcsshsshd_config
        docker exec $c_name bash -c 'mkdir -p varrunsshd'

        echo [$c_name] 步骤4 设置 root 密码...
        docker exec $c_name bash -c echo 'root$root_pwd'  chpasswd

        echo [$c_name] 步骤5 写入环境变量并即时启动服务...
        docker exec $c_name bash -c 'echo service ssh start  root.bashrc'
        docker exec $c_name bash -c 'echo export LD_LIBRARY_PATH=usrlocalcudalib  root.bashrc'
        docker exec $c_name bash -c 'echo export PATH=$PATHusrlocalcudabin  root.bashrc'
        docker exec $c_name bash -c 'echo export PATH=optcondabin$PATH  root.bashrc'
        
        # 写入完环境后，当场在后台把 SSH 服务拉起来
        docker exec $c_name service ssh start

        echo -e ${C_GREEN}[成功] $c_name 部署完毕！共享挂载点为 $c_dir${C_RESET}
        echo -e ${C_GREEN}SSH 服务已在后台即时启动，外网现在可以直接进行 SSH 登录！${C_RESET}
    done

    pause
}

# ==========================================
# 主程序入口循环
# ==========================================
while true; do
    print_header
    echo  [1] 安装依赖 (首次使用必须运行)
    echo  [2] 查看当前系统所有容器
    echo  [3] 启停删除进入 指定容器
    echo  [4] 批量创建容器 
    echo  [0] 退出
    echo 
    read -p $(echo -e ${C_YELLOW}请输入功能编号 ${C_RESET}) choice

    case $choice in
        1) init_host_env ;;
        2) view_containers ;;
        3) manage_single ;;
        4) batch_create ;;
        0) clear; exit 0 ;;
        ) echo -e ${C_RED}无效输入！${C_RESET}; sleep 1 ;;
    esac
done