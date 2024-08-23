#export environment variables
bash ./export.sh

#==========
# Selenium
#==========
echo "Installing Selenium!"
mkdir -p /opt/selenium 
wget --no-verbose http://selenium-release.storage.googleapis.com/3.14/selenium-server-standalone-3.14.0.jar  -O /opt/selenium/selenium-server-standalone.jar && echo 'Selenium Installed successfully' || echo "Selenium installation failed"

#============================================
# Google Chrome - not able to find cleaner way yet
#============================================
echo $'[google-chrome] \n
name=google-chrome \n
baseurl=http://dl.google.com/linux/chrome/rpm/stable/x86_64 \n
enabled=1 \n
gpgcheck=1 \n
gpgkey=https://dl.google.com/linux/linux_signing_key.pub \n' > /etc/yum.repos.d/google-chrome.repo

yum install -y -q https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/desktop-file-utils-0.23-8.el8.x86_64.rpm \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/xdg-utils-1.1.2-5.el8.noarch.rpm \
  https://vault.centos.org/7.9.2009/os/x86_64/Packages/liberation-fonts-common-1.07.2-16.el7.noarch.rpm \
  https://vault.centos.org/7.9.2009/os/x86_64/Packages/liberation-mono-fonts-1.07.2-16.el7.noarch.rpm \
  https://vault.centos.org/7.9.2009/os/x86_64/Packages/liberation-narrow-fonts-1.07.2-16.el7.noarch.rpm \
  https://vault.centos.org/7.9.2009/os/x86_64/Packages/liberation-sans-fonts-1.07.2-16.el7.noarch.rpm \
  https://vault.centos.org/7.9.2009/os/x86_64/Packages/liberation-serif-fonts-1.07.2-16.el7.noarch.rpm \
  https://vault.centos.org/7.9.2009/os/x86_64/Packages/liberation-fonts-1.07.2-16.el7.noarch.rpm \
  https://vault.centos.org/7.9.2009/os/x86_64/Packages/vulkan-filesystem-1.1.97.0-1.el7.noarch.rpm \
  https://vault.centos.org/7.9.2009/os/x86_64/Packages/vulkan-1.1.97.0-1.el7.x86_64.rpm

yum install -y -q google-chrome-stable && echo 'Chrome installed successfully' || echo "Chrome installation failed"

# #============================================
# # Chrome webdriver
# #============================================
# install jq for parsing purpose
yum -y -q install jq

# Version are in the form MAJOR.MINOR.BUILD.PATCH
CHROME_EXACT_VERSION="$(google-chrome --version | awk '{print $3}')"

echo "Installing Chrome web driver for Chrome version $CHROME_EXACT_VERSION..."

# Find the chrome drivers versions and downloads
known_good_versions_with_downloads_json=$(mktemp)
curl -sS -o "$known_good_versions_with_downloads_json" https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json
CHROME_DRIVER_DOWNLOAD_URL=$(jq -r --arg chrome_version "$CHROME_EXACT_VERSION" '.versions[] | select(.version == $chrome_version) | .downloads.chromedriver[] | select(.platform == "linux64") | .url' "$known_good_versions_with_downloads_json")
if [ -z "$CHROME_DRIVER_DOWNLOAD_URL" ]; then
  # Remove patch number and look for a Chrome driver
  CHROME_MAJOR_MINOR_BUILD_VERSION=$(echo "$CHROME_EXACT_VERSION" | awk -F. '{print $1"."$2"."$3}')
  echo "Looking for Chrome Web Driver for Chrome versions $CHROME_MAJOR_MINOR_BUILD_VERSION.XXX"
  CHROME_DRIVER_DOWNLOAD_URL=$(jq -r --arg chrome_version "$CHROME_MAJOR_MINOR_BUILD_VERSION" '[.versions[] | select(.version | startswith($chrome_version)) | .downloads.chromedriver[] | select(.platform == "linux64") | .url] | first//empty' "$known_good_versions_with_downloads_json")
  if [ -z "$CHROME_DRIVER_DOWNLOAD_URL" ]; then
    # Remove build & patch numbers and look for a Chrome driver
    CHROME_MAJOR_MINOR_VERSION=$(echo "$CHROME_EXACT_VERSION" | awk -F. '{print $1"."$2}')
    echo "Looking for Chrome Web Driver for Chrome versions $CHROME_MAJOR_MINOR_VERSION.XXX.XXX"
    CHROME_DRIVER_DOWNLOAD_URL=$(jq -r --arg chrome_version "$CHROME_MAJOR_MINOR_VERSION" '[.versions[] | select(.version | startswith($chrome_version)) | .downloads.chromedriver[] | select(.platform == "linux64") | .url] | first//empty' "$known_good_versions_with_downloads_json")
    if [ -z "$CHROME_DRIVER_DOWNLOAD_URL" ]; then
      # Remove minor, build & patch numbers and look for a Chrome driver
      CHROME_MAJOR_VERSION=$(echo "$CHROME_EXACT_VERSION" | awk -F. '{print $1}')
      echo "Looking for Chrome Web Driver for Chrome versions $CHROME_MAJOR_VERSION.XXX.XXX.XXX"
      CHROME_DRIVER_DOWNLOAD_URL=$(jq -r --arg chrome_version "$CHROME_MAJOR_VERSION" '[.versions[] | select(.version | startswith($chrome_version)) | .downloads.chromedriver[] | select(.platform == "linux64") | .url] | first//empty' "$known_good_versions_with_downloads_json")
      if [ -z "$CHROME_DRIVER_DOWNLOAD_URL" ]; then
        # fallback to a good known version
        echo "No chrome driver version download url found for Chrome $CHROME_MAJOR_VERSION"
        CHROME_DRIVER_DOWNLOAD_URL="https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/117.0.5938.88/linux64/chromedriver-linux64.zip"
        echo "Fall back download url will be $CHROME_DRIVER_DOWNLOAD_URL"
      fi
    fi
  fi
fi

# Install ChromeDriver.
wget $CHROME_DRIVER_DOWNLOAD_URL -P ~/ -O ~/chromedriver_linux64.zip
unzip -o ~/chromedriver_linux64.zip -d ~/
rm -f ~/chromedriver_linux64.zip
mv -f ~/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver
chown root:root /usr/local/bin/chromedriver
chmod 0755 /usr/local/bin/chromedriver

#install xvfb    
yum install -y -q libXScrnSaver \
  mesa-libgbm nss at-spi2-atk libX11-xcb \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/libxkbfile-1.1.0-1.el8.x86_64.rpm \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/xorg-x11-xkb-utils-7.7-28.el8.x86_64.rpm \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/xorg-x11-server-common-1.20.11-23.el8.x86_64.rpm \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/xorg-x11-xauth-1.0.9-12.el8.x86_64.rpm \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/libXdmcp-1.1.3-1.el8.x86_64.rpm \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/libXfont2-2.0.3-2.el8.x86_64.rpm \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/xorg-x11-server-Xvfb-1.20.11-23.el8.x86_64.rpm && echo 'XVFB installed successfully\n' || echo "XVFB installation failed\n"

yum install -y -q https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/libraw1394-2.1.2-5.el8.x86_64.rpm \
  https://vault.centos.org/8-stream/AppStream/x86_64/os/Packages/libavc1394-0.5.4-7.el8.x86_64.rpm

nohup sh -c 'xvfb-run --server-args="$DISPLAY -screen 0 $GEOMETRY -ac +extension RANDR"' >/dev/null 2>&1 & 
nohup sh -c 'java -jar /opt/selenium/selenium-server-standalone.jar -port 4444' >/dev/null 2>&1 &

npmExists='npm -v'
if ! $npmExists
then
    echo "npm could not be found"
    exit
fi

#install protractor command
npm install -g protractor && echo 'Protractor Installed successfully' || echo "Protractor installation failed"

#run protractor to browse page via zap proxy
protractorConfigFile='../uiscripts/conf/protractorConfig.js'
protractor $protractorConfigFile && echo 'Pages browsed successfully' && exit 0 || echo "Page browsing failed"
