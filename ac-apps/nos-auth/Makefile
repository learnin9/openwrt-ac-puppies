#
# Copyright (C) 2014-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=nos-auth
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Chen Minqiang <ptpt52@gmail.com>
PKG_LICENSE:=GPL-2.0
 
include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)/Default
  SECTION:=Applications
  CATEGORY:=Puppies
  DEPENDS:= +kmod-nos
endef

define Package/$(PKG_NAME)
  $(call Package/$(PKG_NAME)/Default)
  TITLE:=User authentication config load script
endef

define Package/$(PKG_NAME)/description
  Web access user authentication app config script
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/nos-auth
endef

define Package/$(PKG_NAME)/postinst
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/nos-auth.init $(1)/etc/init.d/nos-auth
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/nos-auth.config $(1)/etc/config/nos-auth
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/nos-auth.sh $(1)/usr/bin/nos-auth
endef

define Build/Configure
  true
endef

define Build/Prepare
  true
endef

define Build/Compile
  true
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

