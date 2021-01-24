#!/usr/bin/env bash

set -e 
START_TIME=`date +%s`
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"
INFO="[${Green_font_prefix}INFO${Font_color_suffix}]"
ERROR="[${Red_font_prefix}ERROR${Font_color_suffix}]"
TMATE_SOCK="/tmp/tmate.sock"
SERVERPUSH_LOG="/tmp/wechat.log"
CONTINUE_FILE="/tmp/continue"


echo -e "${INFO} Download and install V2ray ..."
# Download and install V2Ray
sudo mkdir /tmp/v2ray
sudo curl -L -H "Cache-Control: no-cache" -o /tmp/v2ray/v2ray.zip https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip
sudo unzip /tmp/v2ray/v2ray.zip -d /tmp/v2ray
sudo install -m 755 /tmp/v2ray/v2ray /usr/local/bin/v2ray
sudo install -m 755 /tmp/v2ray/v2ctl /usr/local/bin/v2ctl
# Remove temporary directory
sudo rm -rf /tmp/v2ray


echo -e "${INFO} Starting V2ray ..."
# V2Ray new configuration
sudo install -d /usr/local/etc/v2ray
cat << EOF > ./config.json
{
    "inbounds": [
        {
            "port": 42600,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "ws"
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom"
        }
    ]
}
EOF

# Run V2Ray
sudo nohup /usr/local/bin/v2ray -config ./config.json > /tmp/v2ray.log 2>&1 &

echo -e "${INFO} I'll rest for 5 seconds ..."
sleep 5

echo -e "${INFO} Downloading Frpc ..."
# Download and install Frpc
sudo mkdir /tmp/frpc
sudo curl -L -H "Cache-Control: no-cache" -o /tmp/frpc/frpc https://getfrp.sh/d/frpc_linux_amd64
sudo install -m 755 /tmp/frpc/frpc /usr/local/bin/frpc

echo -e "${INFO} Starting Frpc ..."
#start up the frp prxoy
sudo nohup /usr/local/bin/frpc -f ${SAKURAFRP_ADDR} > /tmp/frpc.log 2>&1 &



# Install tmate on macOS or Ubuntu
echo -e "${INFO} Setting up tmate ..."
if [[ -n "$(uname | grep Linux)" ]]; then
    curl -fsSL git.io/tmate.sh | bash
elif [[ -x "$(command -v brew)" ]]; then
    brew install tmate
else
    echo -e "${ERROR} This system is not supported!"
    exit 1
fi

# Generate ssh key if needed
[[ -e ~/.ssh/id_rsa ]] || ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -N ""

# Run deamonized tmate
echo -e "${INFO} Running tmate..."
tmate -S ${TMATE_SOCK} new-session -d
tmate -S ${TMATE_SOCK} wait tmate-ready

# Print connection info
TMATE_SSH=$(tmate -S ${TMATE_SOCK} display -p '#{tmate_ssh}')
TMATE_WEB=$(tmate -S ${TMATE_SOCK} display -p '#{tmate_web}')

MSG="
*GitHub Actions - V2ray*

🙊 *V2ray Info*

V2Ray URL: \`${SAKURAFRP_URL}\`
V2Ray Password: \`${UUID}\`

*GitHub Actions - tmate session info:*

⚡ *CLI:*
\`${TMATE_SSH}\`

🔗 *URL:*
${TMATE_WEB}

🔔 *TIPS:*
Run '\`touch ${CONTINUE_FILE}\`' to continue to the next step.
"

if [[ -n "${SERVERPUSHKEY}" ]]; then
    echo -e "${INFO} Sending notice to Wechat..."
    curl -sSX POST "${ServerPush_API_URL:-https://sc.ftqq.com}/${SERVERPUSHKEY}.send" \
        -d "text=新的GAV2ray已就绪" \
        -d "desp=${MSG}" >${SERVERPUSH_LOG}
    SERVERPUSH_STATUS=$(cat ${SERVERPUSH_LOG} | jq -r .errno)
    if [[ ${SERVERPUSH_STATUS} != 0 ]]; then
        echo -e "${ERROR} Wechat message sending failed: $(cat ${SERVERPUSH_LOG})"
    else
        echo -e "${INFO} Wechat message sent successfully!"
    fi
fi

while ((${PRT_COUNT:=1} <= ${PRT_TOTAL:=3})); do
    SECONDS_LEFT=${PRT_INTERVAL_SEC:=10}
    while ((${PRT_COUNT} > 1)) && ((${SECONDS_LEFT} > 0)); do
        echo -e "${INFO} (${PRT_COUNT}/${PRT_TOTAL}) Please wait ${SECONDS_LEFT}s ..."
        sleep 1
        SECONDS_LEFT=$((${SECONDS_LEFT} - 1))
    done
    echo "-----------------------------------------------------------------------------------"
    echo "To connect to this session copy and paste the following into a terminal or browser:"
    echo -e "CLI: ${Green_font_prefix}${TMATE_SSH}${Font_color_suffix}"
    echo -e "URL: ${Green_font_prefix}${TMATE_WEB}${Font_color_suffix}"
    echo -e "TIPS: Run 'touch ${CONTINUE_FILE}' to continue to the next step."
    echo "-----------------------------------------------------------------------------------"
    PRT_COUNT=$((${PRT_COUNT} + 1))
done


while [[ -S ${TMATE_SOCK} ]]; do
    sleep 1
    set -e
    NOW_TIME=`date +%s`
    RUNNER_TIME=`echo $START_TIME $NOW_TIME | awk '{print $2-$1}'`
    
    if [[ -e ${CONTINUE_FILE} ]] || ((${RUNNER_TIME} > 21500)); then

        echo -e "${INFO} Now stop the Frpc ..."
            
        FRPC_PID=`sudo ps -aux|grep frp| grep -v grep | cut -d ' ' -f 2`
        sudo kill -9 FRPC_PID

        if [[ -n "${SERVERPUSHKEY}" ]]; then
            echo -e "${INFO} Sending message to Wechat..."
            curl -sSX POST "${ServerPush_API_URL:-https://sc.ftqq.com}/${SERVERPUSHKEY}.send" \
                -d "text=前一GAV2ray设备已下线！" \
                -d "desp=前一GAV2ray设备已下线！" >${SERVERPUSH_LOG}
            SERVERPUSH_STATUS=$(cat ${SERVERPUSH_LOG} | jq -r .errno)
            if [[ ${SERVERPUSH_STATUS} != 0 ]]; then
                echo -e "${ERROR} Wechat message sending failed: $(cat ${SERVERPUSH_LOG})"
            else
                echo -e "${INFO} Wechat message sent successfully!"
            fi
        fi
    
        echo -e "${INFO} Continue to the next step."
        exit 0
    fi
done



# ref: https://github.com/csexton/debugger-action/blob/master/script.sh
