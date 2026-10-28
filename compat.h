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
#include <linux/types.h>

/* ---- class_create() ---------------------------------------------------- */
/* v6.4 removed the struct module *owner argument. */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0)
#define wcn_class_create(name)		class_create(THIS_MODULE, (name))
#else
#define wcn_class_create(name)		class_create(name)
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
		int __wcn_gpio = of_get_named_gpio((np), (prop), (idx));\
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

#endif /* __UWE5622_COMPAT_H */
