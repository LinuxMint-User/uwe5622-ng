/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Kernel API compatibility shims for the out-of-tree uwe5622 driver.
 *
 * Everything in here is a compile-time equivalent of the vendor 6.1 code:
 * runtime behaviour must stay identical.  Each shim is selected with
 * LINUX_VERSION_CODE so the same sources still build on 6.1 and 6.18.
 */
#ifndef __UWE5622_COMPAT_H
#define __UWE5622_COMPAT_H

#include <linux/version.h>
#include <linux/device.h>
#include <linux/gpio.h>
#include <linux/of.h>
#include <linux/pm_wakeup.h>
#include <linux/string.h>
#include <linux/timer.h>
#include <linux/types.h>

/* ---- strncpy() --------------------------------------------------------- */
/*
 * 7.2 dropped strncpy() from linux/string.h (only the strscpy family is
 * left).  Several callers rely on POSIX semantics, i.e. the tail of a
 * fixed-size field being zero-filled, so keep them instead of rewriting
 * every site to strscpy().
 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 2, 0)
static inline char *wcn_strncpy(char *dest, const char *src, size_t count)
{
	size_t len = strnlen(src, count);

	memcpy(dest, src, len);
	if (len < count)
		memset(dest + len, 0, count - len);

	return dest;
}
#else
#define wcn_strncpy(dest, src, count)	strncpy((dest), (src), (count))
#endif

/* ---- class_create() ---------------------------------------------------- */
/* v6.4 removed the struct module *owner argument. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0)
#define wcn_class_create(name)		class_create(THIS_MODULE, (name))
#else
#define wcn_class_create(name)		class_create(name)
#endif

/* v6.4 made the class and attribute passed to class attribute callbacks
 * const. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0)
typedef struct class wcn_class_t;
typedef struct class_attribute wcn_class_attr_t;
#else
typedef const struct class wcn_class_t;
typedef const struct class_attribute wcn_class_attr_t;
#endif

/* ---- wakeup_source create/add/remove/destroy --------------------------- */
/*
 * Upstream only keeps wakeup_source_register()/wakeup_source_unregister().
 * register(NULL, name) is the exact equivalent of create()+add() with no
 * device association, unregister() of remove()+destroy().
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0)
#define wcn_wakeup_source_create(name)	wakeup_source_create(name)
#define wcn_wakeup_source_add(ws)	wakeup_source_add(ws)
#define wcn_wakeup_source_remove(ws)	wakeup_source_remove(ws)
#define wcn_wakeup_source_destroy(ws)	wakeup_source_destroy(ws)
#else
#define wcn_wakeup_source_create(name)	wakeup_source_register(NULL, (name))
#define wcn_wakeup_source_add(ws)	do { (void)(ws); } while (0)
#define wcn_wakeup_source_remove(ws)	do { (void)(ws); } while (0)
#define wcn_wakeup_source_destroy(ws)	wakeup_source_unregister(ws)
#endif

/* ---- of_get_named_gpio() ----------------------------------------------- */
/*
 * 7.2 removed linux/of_gpio.h and of_get_named_gpio() together with the rest
 * of the legacy integer-base OF lookup.  The driver still tracks plain GPIO
 * numbers, so resolve the line through the descriptor based API and hand the
 * number back after dropping the temporary descriptor; the number stays
 * valid for the later gpio_request()/gpio_direction_*() calls.
 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 2, 0)
#include <linux/gpio/consumer.h>

static inline int wcn_of_get_named_gpio(const struct device_node *np,
					const char *propname, int index)
{
	struct gpio_desc *desc;
	int gpio;

	desc = fwnode_gpiod_get_index((struct fwnode_handle *)of_fwnode_handle(np),
				      propname, index, GPIOD_ASIS, "uwe5622");
	if (IS_ERR(desc))
		return PTR_ERR(desc);

	gpio = desc_to_gpio(desc);
	gpiod_put(desc);

	return gpio;
}
#else
#include <linux/of_gpio.h>
#define wcn_of_get_named_gpio(np, prop, idx)				\
	of_get_named_gpio((np), (prop), (idx))
#endif

/* ---- of_get_named_gpio_flags() ----------------------------------------- */
/*
 * Removed upstream.  of_get_named_gpio() cannot return the sunxi per-pin
 * gpio_config, so on new kernels only config->gpio is filled; the remaining
 * fields were used for a debug print only.
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0)
#define wcn_of_get_named_gpio_flags(np, prop, idx, cfg)			\
	of_get_named_gpio_flags((np), (prop), (idx),			\
				(enum of_gpio_flags *)(cfg))
#else
#define wcn_of_get_named_gpio_flags(np, prop, idx, cfg)			\
	({								\
		int __wcn_gpio = wcn_of_get_named_gpio((np), (prop), (idx));\
									\
		(cfg)->gpio = (__wcn_gpio >= 0) ? (u32)__wcn_gpio : 0;	\
		__wcn_gpio;						\
	})
#endif

/* ---- devm_gpio_request() ----------------------------------------------- */
/*
 * Removed upstream.  The caller sets the line to input right afterwards, so
 * GPIOF_IN keeps the same end state.
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0)
#define wcn_devm_gpio_request(dev, gpio, label)				\
	devm_gpio_request((dev), (gpio), (label))
#else
#define wcn_devm_gpio_request(dev, gpio, label)				\
	devm_gpio_request_one((dev), (gpio), GPIOF_IN, (label))
#endif

/* ---- timers ------------------------------------------------------------ */
/*
 * del_timer()/del_timer_sync()/from_timer() were removed upstream in favour
 * of timer_delete()/timer_delete_sync()/container_of().
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0)
#define wcn_timer_delete(t)		del_timer(t)
#define wcn_timer_delete_sync(t)	del_timer_sync(t)
#define wcn_from_timer(var, timer, member) from_timer(var, timer, member)
#else
#define wcn_timer_delete(t)		timer_delete(t)
#define wcn_timer_delete_sync(t)	timer_delete_sync(t)
#define wcn_from_timer(var, timer, member)				\
	container_of(timer, typeof(*(var)), member)
#endif

/* ---- generic netlink --------------------------------------------------- */
/*
 * genl_family pre_doit/post_doit take a const struct genl_split_ops * once
 * split ops exist; 6.1 still passes const struct genl_ops *.
 */
struct genl_ops;
struct genl_split_ops;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 3, 0)
typedef const struct genl_split_ops *wcn_genl_ops_t;
#else
typedef const struct genl_ops *wcn_genl_ops_t;
#endif

/* ---- tty_operations.write() -------------------------------------------- */
/* v6.6 changed write() to return ssize_t and take size_t. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 6, 0)
typedef int wcn_tty_write_ret;
typedef int wcn_tty_write_len;
#else
typedef ssize_t wcn_tty_write_ret;
typedef size_t wcn_tty_write_len;
#endif

/* ---- platform_driver.remove() ------------------------------------------ */
/* v6.11 changed the remove callback to return void. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 11, 0)
#define wcn_remove_ret		int
#define wcn_remove_return	return 0
#else
#define wcn_remove_ret		void
#define wcn_remove_return	return
#endif

/* ---- cfg80211_ops ------------------------------------------------------ */
/*
 * change_beacon() switched to struct cfg80211_ap_update in 6.7.
 * set_wiphy_params() grew radio_idx and tdls_mgmt() grew link_id in 6.17.
 */
#define WCN_CFG80211_AP_UPDATE \
	(LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0))
#define WCN_CFG80211_RADIO_IDX \
	(LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0))
#define WCN_CFG80211_TDLS_LINK_ID \
	(LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0))

/*
 * 7.2 switched the key and station callbacks from struct net_device * to
 * struct wireless_dev *, and the new_sta/del_sta notifications followed.
 * remain_on_channel() also grew the target address.
 */
#define WCN_CFG80211_WDEV_OPS \
	(LINUX_VERSION_CODE >= KERNEL_VERSION(7, 2, 0))

#if WCN_CFG80211_WDEV_OPS
#define wcn_cfg80211_arg_t		struct wireless_dev
#define wcn_cfg80211_ndev(arg)		((arg)->netdev)
#define wcn_cfg80211_new_sta(vif, addr, sinfo, gfp) \
	cfg80211_new_sta(&(vif)->wdev, (addr), (sinfo), (gfp))
#define wcn_cfg80211_del_sta(vif, addr, gfp) \
	cfg80211_del_sta(&(vif)->wdev, (addr), (gfp))
#define wcn_cfg80211_roc_addr_param	, const u8 *rx_addr
#else
#define wcn_cfg80211_arg_t		struct net_device
#define wcn_cfg80211_ndev(arg)		(arg)
#define wcn_cfg80211_new_sta(vif, addr, sinfo, gfp) \
	cfg80211_new_sta((vif)->ndev, (addr), (sinfo), (gfp))
#define wcn_cfg80211_del_sta(vif, addr, gfp) \
	cfg80211_del_sta((vif)->ndev, (addr), (gfp))
#define wcn_cfg80211_roc_addr_param
#endif

#endif /* __UWE5622_COMPAT_H */
