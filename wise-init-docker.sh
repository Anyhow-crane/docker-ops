#!/bin/bash 

# 此安装文件需要centos7-64位系统

# 获取全部参数信息
wise_all_params=$@

# 判断是否为root用户，如果是管理员用户使用sudo
wise_user="$(id -un 2> /dev/null || true)"
wise_bash_c='bash -c'
if [ "$wise_user" != 'root' ]; then
	wise_bash_c='sudo -E bash -c'	
fi

# 获取工作目录全路径，为后面创建管理员目录，和安装docker工作目录准备
echo "-----------------------"
echo "安装docker需要设置您的工作目录，请输入全路径，直接回车，使用默认路径 /data "
echo "如果使用非默认目录，需要提前创建此目录，没有的请使用 ctrl+c 退出程序，mkdir 目录"
#echo "工作目录最好使用挂载目录，安装docker后，设置为镜像、容器等的存储目录"
#echo "请输入工作目录全路径"
#read wise_work_path

wise_use_dir=0
for dir in $wise_all_params; do
  if [ -d "$dir" ]; then
		wise_work_path=$dir
		wise_use_dir=1
		echo "使用工作路径$wise_work_path"
	fi
done
if [ "$wise_use_dir" = 0 ]; then
	wise_work_path="/data"
	if [ ! -d "$wise_work_path" ]; then
		$wise_bash_c "mkdir /data"
	fi
	echo "使用默认工作路径/data"
fi

# 获取开放防火墙端口
echo "-----------------------"
echo "设置需要开放防火墙的端口号，可以直接回车不做修改，多个端口用空格隔开，例如：3306 8080"
echo "安装失败后，再次安装时，不要再次设置"
#echo "请输入需要开放防火墙的端口号"
#read wise_open_ports

# 创建用户的名称
wise_user_name="wiseloong"

# 是否需要在工作目录创建wise的管理员用户
# echo "-----------------------"
# echo "默认创建$wise_user_name用户，安装后请切换此$wise_user_name用户继续操作"
#echo "是否需要在工作目录下创建名为$user_name的管理员用户，以后可切换此用户操作服务器"
#echo "当选择y后安装失败，再次安装时，还要选择y，这时不会再重复创建用户，否则无法把$user_name用户加入docker组"
#read -r -p "是否创建$user_name管理员用户？ [y/n] " 

wise_add_user=0
for param in $wise_all_params
do
   case $param in
    -u) wise_add_user=1
  ;;
esac
done

# 配置docker-daemon.json 信息
wise_daemon_file="/etc/docker/daemon.json"
wise_daemon_data="{
  \"data-root\": \"$wise_work_path/docker\",
  \"selinux-enabled\": false
}"

# 判断是否有某个命令
wise_command_exists() {
	command -v "$@" > /dev/null 2>&1
}

# 添加dns
wise_add_dns() {
	dns=$(grep -c "nameserver 114.114.114.114" /etc/resolv.conf)
	if [ "$dns" -eq '0' ]; then
		$wise_bash_c "echo 'nameserver 114.114.114.114' >> /etc/resolv.conf"
		echo "添加dns 114.114.114.114 "
	fi
}

# 关闭selinux
wise_close_selinux() {
	wise_selinux="$(getenforce 2>/dev/null || true)"
	if [ "$wise_selinux" == 'Enforcing' ]; then
		$wise_bash_c "sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config"
		$wise_bash_c "setenforce 0"
		echo "关闭selinux - 完成"
	fi
}

# 开放防火墙端口
wise_open_port() {
	wise_is_open_port=0
  for port in $wise_all_params; do
    if [ "$port" -gt 0 ] 2> /dev/null ; then
			is_open="$($wise_bash_c 'firewall-cmd --query-port='$port'/tcp')"
		  if [ "yes" == $is_open ] ; then
			  echo "端口$port---已经开放！"
		  else
			  wise_is_open_port=1
		  	echo "正在开放端口$port---"
		  	$wise_bash_c "firewall-cmd --zone=public --add-port=$port/tcp --permanent"
			fi
		fi
	done
	if [ "$wise_is_open_port" = 1 ]; then
		echo "重新加载防火墙---"
		$wise_bash_c "firewall-cmd --reload"
	fi 
}

# 添加管理员账号默认为wise，如果需要创建其他管理员名称，修改上面的user_name名称
wise_add_wise() {
	if [ "$wise_add_user" = 0 ]; then
		wise="$(id -un $wise_user_name 2> /dev/null || true)"
		if [ "$wise" != "$wise_user_name" ]; then
			# echo "正在创建管理员$wise_user_name！"
			# $wise_bash_c "useradd -g wheel -d $wise_work_path/$wise_user_name $wise_user_name"
			# $wise_bash_c "passwd $wise_user_name"
			echo "-----------------------"
			echo "正在创建用户$wise_user_name！"
			$wise_bash_c "useradd -d $wise_work_path/$wise_user_name $wise_user_name"
			echo "wiseloong" | $wise_bash_c "passwd $wise_user_name --stdin"
			echo "用户$wise_user_name创建完成，密码为--------wiseloong--------，请妥善保管！"
			echo "请安装完毕后切换此账号操作！"
		fi
	fi
}

# docker初始化配置
wise_after_docker() {
	if wise_command_exists docker ; then
		echo "设置docker初始化配置---"
		$wise_bash_c "systemctl enable docker"
		if [ ! -d "/etc/docker" ]; then
			$wise_bash_c "mkdir /etc/docker"
		fi
		if [ ! -f "$wise_daemon_file" ];then
			$wise_bash_c "cat > $wise_daemon_file <<-EOF
			$wise_daemon_data 
			EOF"
		fi
		if [ "$wise_add_user" = 0 ]; then
			$wise_bash_c "usermod -aG docker $wise_user_name"
			echo "添加用户$wise_user_name到docker用户组 - 完成"
			echo "退出当前ssh，重新连接用户$wise_user_name，即可愉快的使用docker。。。"
		else
			if [ "$wise_user" != 'root' ]; then
				$wise_bash_c "usermod -aG docker $wise_user"
				echo "添加当前用户$wise_user到docker用户组 - 完成"
				echo "退出当前ssh，重新连接当前用户$wise_user，即可愉快的使用docker。。。"
			fi
		fi
		$wise_bash_c "systemctl restart docker"
		echo "docker已启动！"
	fi
}

# 安装docker-compose
wise_install_docker_compose() {
	if wise_command_exists docker-compose ; then
		echo "已经安装docker-compose，请使用命令 docker-compose --version 查看！"
	else
	  echo "-----------------------"
		echo "开始安装docker-compose---"
	  $wise_bash_c "curl -L 'http://112.27.251.72:60020/docker-compose-Linux-x86_64' -o /usr/local/bin/docker-compose"
	  $wise_bash_c "chmod +x /usr/local/bin/docker-compose"
		echo "docker-compose安装 - 完成！"
	fi
}

# 安装docker
wise_install_docker() {
	if wise_command_exists docker ; then
		echo "已经安装docker，请使用命令 docker info 查看！"
	else
	  echo "-----------------------"
		echo "开始安装docker---"
		curl -fsSL https://github.com/Anyhow-crane/docker-ops/blob/master/get-docker.sh?raw=true | bash -s docker --mirror Aliyun
		wise_after_docker
		if wise_command_exists docker ; then
			echo "docker安装 - 完成！"
			wise_install_docker_compose
		else
			echo "docker安装 - 失败,请重新安装！"
		fi
	fi
}

# wise_add_dns
wise_close_selinux
wise_open_port
wise_add_wise
wise_install_docker
