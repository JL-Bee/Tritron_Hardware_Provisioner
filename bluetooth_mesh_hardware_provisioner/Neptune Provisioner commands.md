```
~>_____mesh/
~>   |_ factory_reset
~>   |_ provision/scan/get
~>   |_ provision/provision
~>   |_ provision/result/get
~>   |_ provision/status/get
~>   |_ provision/last_addr/get
~>   |_ device/reset
~>   |_ device/remove
~>   |_ device/label/get
~>   |_ device/label/set
~>   |_ device/identify/set
~>   |_ device/list
~>   |_ device/sub/add
~>   |_ device/sub/remove
~>   |_ device/sub/reset
~>   |_ device/sub/get
~>   |_ dali_lc/idle_cfg/set
~>   |_ dali_lc/idle_cfg/get
~>   |_ dali_lc/trigger_cfg/set
~>   |_ dali_lc/trigger_cfg/get
~>   |_ dali_lc/identify/set
~>   |_ dali_lc/identify/get
~>   |_ dali_lc/override/set
~>   |_ dali_lc/override/get
~>   |_ radar/cfg/set
~>   |_ radar/cfg/get
~>   |_ radar/enable/set
~>   |_ radar/enable/get
```

---
## `factory_reset`
Removes every device from the local database (without unprovisioning) and then reboots the provisioner. The provisioning shell sends another `$ready` to indicate it is active again.
#### Args  🛠️
None.

#### Output  ✨
None.

#### Return  ↩️
Always `$ok`.

#### Example  🧪

```c
mesh/factory_reset
~>$ok

~>$ready
```
---
## `provision/scan/get`
Returns a list of provisionable devices.
#### Args  🛠️
None

#### Output  ✨
It prints every UUID (if any) as a hex string, one UUID per line. When no provisionable devices are found, no lines are printed.

#### Return  ↩️
Always returns `$ok`.

#### Example  🧪

```
mesh/provision/scan/get
~>0c305584745b4c09b3cfaa7b8ba483f6
~>0c305224759afcbeefcfaa7b84a488f6
~>$ok
```
---
## provision/provision
Provisions a device and adds it to the local database.

#### Args  🛠️
- UUID: 32 character hex string (without 0x)

#### Example  🧪
```
mesh/provision/provision 0c305584745b4c09b3cfaa7b8ba483f6
~>$ok
```
---
## `provision/result/get`
Returns the result of the last provision task. Is reset at the begin of a new provision task.
If the task is still busy in progress, or no task has finished since boot, it returns -3 (ESRCH).
#### Args  🛠️
None

#### Output  ✨
0 when provision task has finished succesfully, or a negative errno code on failure.

#### Return  ↩️
Returns `$error` when no provision task has finished, or `$ok` if it has (no matter if it was successful or not).

#### Example  🧪
```
mesh/provision/result/get
~>0
~>$ok
```
---
## provision/last_addr/get
Returns the address of the last provisioned node. Is reset at the begin of a new provision task.

#### Args  🛠️
None

#### Output  ✨
Address of last provisioned device as an 4 character hex string prefixed with `0x`. Or nothing if provision task has not completed successfully.
#### Return  ↩️
`$ok` when the last provisioning task ended successfully, or `$error` when it didn't.
#### Example  🧪
```
mesh/provision/last_addr/get
~>0x0002
~>$ok
```
---
## `device/reset`
 Unprovisions a device and removes it from the provisioner's database. The unprovision state can later be requested through.

#### Args  🛠️
1. **Node Address**: Address of the node to reset.
2. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.
#### Output  ✨
None.

#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.
#### Example  🧪

```c
mesh/device/reset 0x0003 3000
~>$ok
```
---
## `device/remove`
Removes a device from the provisioner database **without** unprovisioning them.
#### Args  🛠️
1. **Node Address**: Address of the node to remove.

#### Output  ✨
None

#### Return  ↩️
`$ok` if the node was removed, or `$error` if not.

#### Example  🧪

```c
mesh/device/remove 0x0003
~>$ok
```
---
## `device/label/get`
Get the device label stored that is in the provisioners database.

#### Args  🛠️
1. **Node Address**: Address of the node whose label to get.

#### Output  ✨
The label

#### Return  ↩️
`$ok` if the task ended successfully, or `$error` if it didn't.


#### Example  🧪

```c
mesh/device/label/get 3
~>"Hello-world"
~>$ok
```
---
## `device/label/set`

#### Args  🛠️
1. **Node Address**: Address of the node to get the label off.
2. **Label** to store (max 32 char).

#### Output  ✨
None.


#### Return  ↩️
`$ok` if the label was updated successfully, or `$error` if it wasn't

#### Example  🧪

```c
mesh/device/label/set 3 "Hello-world"
~>$ok
```
---
## `device/identify/set`
Identify the device via the Bluetooth mesh health model. This feature can be ignored as it does the same as [[#dali_lc/identify/set]]. It's still present for development testing purposes.


#### Args  🛠️
1. **Node Address**: Address to identify.
2. **Short Duration**: The duration of the identify.
	0: Identify off.
	1..255: identify duration in seconds.

#### Output  ✨
None.

#### Return  ↩️
`$ok` if the identify set task has scheduled, or `$error` otherwise.


#### Example  🧪

```c
mesh/device/identify/set 3 202
~>$ok
```
---
## `device/list`
Prints a list of all devices stored in the provisioners database. Each item consists of the node's (root element) address and UUID.
#### Args  🛠️
None.
#### Output  ✨
Each item consists of the address, written as 4 character hex string prefixed with `0x`, and the UUID separated by a `,` (comma). If no devices were provisioned, the command will print nothing (besides the normal return).

#### Return  ↩️
Always `$ok`.
#### Example  🧪

```c
mesh/device/list
~>0x0002,0c305224759afcbeefcfaa7b84a488f6
~>0x0003,0c305584745b4c09b3cfaa7b8ba483f6
~>$ok
```
---
## `device/sub/add`
Add a group address to the subscribe list of a node.
#### Args  🛠️
1. **Node Address**: Addressof the node to add the group address to.
2. **Subscribe Address**: Group address that the node should subscribe to.
3. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.
#### Output  ✨
None.

#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.

#### Example  🧪

```c
mesh/device/sub/add 3 0xc002 3000
~>$ok
```
---
##  `device/sub/remove`
Remove a group address from the subscribe list of a node.
#### Args  🛠️
1. **Node Address**: Addressof the node to remove the group address from.
2. **Subscribe Address**: Group address that should be removed from the node's subscribe list.
3. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
None.
#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.

#### Example  🧪

```c
mesh/device/sub/remove 3 0xc002 3000
~>$ok
```
---
## `device/sub/reset`
Resets the subscribe list of a node, which only configures it to subscribe to itself.
#### Args  🛠️
1. **Node Address**: Addressof the node to reset the subscribe address list of.
2. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
None.

#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.

#### Example  🧪

```c
mesh/device/sub/reset 3 3000
~>$ok

```

---
## `device/sub/get`
Prints all subscribed group addresses of a specific node. These group addresses are printed from the provisioner database, and not fetched from the actual device.
#### Args  🛠️
1. **Node Address**: Addressof the node to show the subscribe addresses from.

#### Output  ✨
A list of all group addresses the node is subscribed to. Each item in the list contains one address, printed as a 4 character hex string prefixed with `0x`. If the node is not subscribed to any group address, it will print nothing (besides the normal return).

#### Return  ↩️
Always `$ok`.

#### Example  🧪

```c
mesh/device/sub/get 3
~>$ok
```
---
## `dali_lc/idle_cfg/set`
Set the Dali LC idle configuration of the device, consisting of the arc level and fade time ([[#Appendix A Fade time]]]).
#### Args  🛠️
1. **Address**: The node or group address to publish this configuration to.
2. **Idle arc** (0..254): The arc level of that the driver should take in the idle state.
3. **Fade time**: The time it takes for the light to get to idle state. This fade time gets ignored by the **trigger fade out time**.
4. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
When timeout is greater than 0, and the task ended successfully before the timeout expired, it prints the **idle arc level** and **idle fade time** from the device acknowledgement. The values are printed as decimal values, separated by a `,` (comma), as shown below.
```
{arc},{fade}
```

If timeout is 0, the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).

#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.

#### Example  🧪

```c
mesh/dali_lc/idle_cfg/set 3 0 4 3000
~>0,4
~>$ok
```
---
## `dali_lc/idle_cfg/get`

Get the Dali LC idle configuration of the device, consisting of the arc level and fade time ([[#Appendix A Fade time]]]).
#### Args  🛠️
1. **Node address**: The address to of the node to request the configuration from.
2. **Timeout**: Timeout in milliseconds. Must be greater than 0.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
When the task ended successfully before the timeout expired, it prints the **idle arc level** and **idle fade time** from the device. The values are printed as decimal values, separated by a `,` (comma), as shown below.
```
{arc},{fade}
```

If the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).

#### Return  ↩️
It returns `$ok` if the task ended successfully before the timeout expired, or $error if it didn't.
#### Example  🧪

```c
mesh/dali_lc/idle_cfg/get 3 3000
~>0,4
~>$ok
```
---
## `dali_lc/trigger_cfg/set`

  Set the Dali LC trigger configuration of the device, consisting of the arc level, fade in time ([[#Appendix A Fade time]]]), fade out time ([[#Appendix A Fade time]]]), and hold time. The Dali LC reaches this state when it receives a trigger from e.g., the a motion sensor server.
#### Args  🛠️
1. **Address**: The node or group address to publish this configuration to.
2. **Arc level** (0..254): The arc level of that the driver should take in the idle state.
3. **Fade in time**: The time it takes for the light to reach the trigger arc level when in the trigger LC state.
4. **Fade out time**: The time it takes for the light to reach the idle arc level when leaving the trigger LC state.
5. **Hold time** (0..65535): The time in seconds the device remains in the trigger state since the last received trigger. Hold time 0 means that triggers get ignored.
6. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
When timeout is greater than 0, and the task ended successfully before the timeout expired, it prints the **arc level**, **fade in time**, **fade out time**, and **hold time** from the device acknowledgement. The values are printed as decimal values, separated by a `,` (comma), as shown below.
```
{arc},{fade_in},{fade_out},{hold_time}
```

If timeout is 0, the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).
#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.

#### Example  🧪

```c
mesh/dali_lc/trigger_cfg/set 3 254 0 7 60 3000
~>254,0,7,60
~>$ok
```
---
## `dali_lc/trigger_cfg/get`
Get the Dali LC trigger configuration of the device, consisting of the arc level, fade in time ([[#Appendix A Fade time]]]),  fade out time ([[#Appendix A Fade time]]]), and hold time.
#### Args  🛠️
1. **Node address**: The address to of the node to request the configuration from.
2. **Timeout**: Timeout in milliseconds. Must be greater than 0.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
When the task ended successfully before the timeout expired,it prints the **arc level**, **fade in time**, **fade out time**, and **hold time** from the device. The values are printed as decimal values, separated by a `,` (comma), as shown below.
```
{arc},{fade_in},{fade_out},{hold_time}
```

If the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).
#### Return  ↩️
It returns `$ok` if the task ended successfully before the timeout expired, or $error if it didn't.
#### Example  🧪

```c
mesh/dali_lc/trigger_cfg/get 3 3000
~>254,0,7,60
~>$ok
```
---
## `dali_lc/identify/set`

Make the device identify itself through the Dali LC module. Identify has the highest light control (LC) priority.
#### Args  🛠️
1. **Address**: The node or group address to publish the command to.
2. **Duration**: The duration of the identify.
	0: Identify off.
	\[1..65534\]: Identify duration in seconds.
	65535: Identify lasts until next reboot.
3. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
When timeout is greater than 0, and the task ended successfully before the timeout expired, it prints the remaining time (duration) from the device acknowledgement. The value is printed as decimal values.

#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.
#### Example  🧪

```c
mesh/dali_lc/identify/set 3 60 3000
~>60
~>$ok
```
---
## `dali_lc/identify/get`

Get the remaining time of the Dali LC identify state.

#### Args  🛠️
1. **Node address**: The address to of the node to request the configuration from.
2. **Timeout**: Timeout in milliseconds. Must be greater than 0.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
If the task ended successfully before the timeout expired, the command prints the remaining identify time from the device. The value is printed as decimal values.

If the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).

Remaining time value describes the following:

| Value    | Description                         |
| -------- | ----------------------------------- |
| 0        | Identify inactive                   |
| 1..65534 | Remaining identify time in seconds. |
| 65535    | Identify lasts until reboot.        |

#### Return  ↩️
It returns `$ok` if the task ended successfully before the timeout expired, or $error if it didn't.
#### Example  🧪

```c
mesh/dali_lc/identify/get 3 3000
~>12
~>$ok
```
---
## `dali_lc/override/set`

  Override the light level of a node, using the arc level, fade time ([[#Appendix A Fade time]]), and duration.
#### Args  🛠️
1. **Address**: The node or group address to publish the command to.
2. **Arc level** (0..254): Arc level during the override period.
3. **Fade Time**: Fade time to use when transitioning to override arc level.
4. **Duration**: The duration of the identify.
	0: Identify off.
	\[1..65534\]: Identify duration in seconds.
	65535: Identify lasts until next reboot.
5. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
When timeout is greater than 0, and the task ended successfully before the timeout expired, it prints the arc level, fade time, and remaining time (duration) from the device acknowledgement. The values are printed as decimal values, separated by a `,` (comma), as shown below.
```
{arc},{fade},{duration}
```

#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.
#### Example  🧪

```c
mesh/dali_lc/override/set 3 254 0 60 3000
~>254,0,60
~>$ok
```

## `dali_lc/override/get`

Get the arc level, fade time and remaining time of the active override.
#### Args  🛠️
1. **Node address**: The address to of the node to request the configuration from.
2. **Timeout**: Timeout in milliseconds. Must be greater than 0.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
If the task ended successfully before the timeout expired, the command prints the arc level, used fade time, and remaining time from the device. The values are printed as decimal values, separated by a `,` (comma), as shown below.

```
{arc},{fade},{duration}
```


Remaining time value describes the following:

| Value    | Description                        |
| -------- | ---------------------------------- |
| 0        | Override inactive                  |
| 1..65534 | Remaining verride time in seconds. |
| 65535    | Override lasts until reboot.       |

If the override is inactive, the arc level and fade time are `255`.

If the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).
#### Return  ↩️
It returns `$ok` if the task ended successfully before the timeout expired, or $error if it didn't.
#### Example  🧪

```c
mesh/dali_lc/identify/get 3 3000
~>12
~>$ok
```
---
## `radar/cfg/set`

  Set the radar configuration configuration of the device, consisting of the threshold band (mV), cross count threshold, sample interval (ms), and buffer dept.
#### Args  🛠️
1. **Address**: The node or group address to publish this configuration to.
2. **Threshold band** (0..1650): Indicates the max voltage from the baseline in millivolts. Default 210.
3. **Cross count threshold** (1..500) The minimum number of measured samples within a buffer that must be outside (or have "crossed") the threshold band for the radar module to detect it as motion. Default 31.
4. **Sample interval** (1..2047): The time between each sample in milliseconds. Default 5.
5. **Buffer dept** (0..500): The number of samples within the circular buffer. Default 500.
6. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.
#### Output  ✨
When timeout is greater than 0, and the task ended successfully before the timeout expired, it prints the threshold band, cross count threshold, sample interval, and buffer dept from the device acknowledgement. The values are printed as decimal values, separated by a `,` (comma), as shown below.
```
{band_thresh},{cross_count},{sample_int},{buff_dept}
```

If timeout is 0, the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).
#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.

#### Example  🧪

```c
mesh/radar/cfg/set 3 210 31 5 500 3000
~>210,31,5,500
~>$ok
```
---
## `radar/cfg/get`

  Get the radar configuration configuration of the device, consisting of the threshold band (mV), cross count threshold, sample interval (ms), and buffer dept.
#### Args  🛠️
1. **Node address**: The address to of the node to request the configuration from.
2. **Timeout**: Timeout in milliseconds. Must be greater than 0.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
When the task ended successfully before the timeout expired, it prints the threshold band, cross count threshold, sample interval, and buffer dept from the device. The values are printed as decimal values, separated by a `,` (comma), as shown below.
```
{band_thresh},{cross_count},{sample_int},{buff_dept}
```

If the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).
#### Return  ↩️
It returns `$ok` if the task ended successfully before the timeout expired, or $error if it didn't.
#### Example  🧪

```c
mesh/radar/cfg/get 3 3000
~>210,31,5,500
~>$ok
```
---
## `radar/enable/set`

Enable or disable the radar module. When disabled, the radar module will not publish any motion events.
#### Args  🛠️
1. **Address**: The node or group address to publish this configuration to.
2. **Enable** (0/1): State to indicate that the radar should enable/disable.
3. **Timeout**: Timeout in milliseconds.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.
#### Output  ✨
When timeout is greater than 0, and the task ended successfully before the timeout expired, it prints the enabled state from the device acknowledgement. The value is printed as a decimal boolean.

If timeout is 0, the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).
#### Return  ↩️
With timeout 0, it returns `$ok` if the task was scheduled successfully, or `$error` if it didn't.
With timeout greater than 0, it returns `$ok` if the task ended successfully before the timeout expired, or `$error` if it didn't.

#### Example  🧪

```c
mesh/radar/enable/set 3 1 3000
~>1
~>$ok
```

---
## `radar/enable/get`

Get the enable state of the radar module.
#### Args  🛠️
1. **Node address**: The address to of the node to request the configuration from.
2. **Timeout**: Timeout in milliseconds. Must be greater than 0.

>[!tip] About timeouts
> When timeout is 0, the command returns `$ok` after scheduling the task. When the timeout is greater than zero, the task blocks and waits for the timeout to expire, or the task to end. When the task ended successfully, it returns an `$ok`, or an `$error` when the timeout expired, or the task failed.
>
> When using a command for a **get** message, the timeout must be **greater than** 0. When running a command that sends something using a **group address**, the timeout must be 0. For other tasks with a timeout targeting a single device, it is recommended to have a timeout greater than 0 to ensure the message has been received correctly.
>
> The recommended default timeout value is 3000 ms.

#### Output  ✨
When the task ended successfully before the timeout expired, it prints the radar enable state from the device. The value is printed as a decimal boolean.

If the timeout expired, or the task didn't end successfully, this commands print nothing (besides the normal return).
#### Return  ↩️
It returns `$ok` if the task ended successfully before the timeout expired, or $error if it didn't.
#### Example  🧪

```c
mesh/radar/enable/set 3 3000
~>1
~>$ok
```
---
# Appendix A: Fade time

| Value | Duration |
| ----- | -------- |
| 0     | 0s       |
| 1     | 0.5s     |
| 2     | 1s       |
| 3     | 1.5s     |
| 4     | 2s       |
| 5     | 3s       |
| 6     | 4s       |
| 7     | 6s       |
| 8     | 8s       |
| 9     | 10s      |
| 10    | 15s      |
| 11    | 20s      |
| 12    | 30s      |
| 13    | 45s      |
| 14    | 60s      |
| 15    | 90s      |
| 16    | 2m       |
| 17    | 3m       |
| 18    | 4m       |
| 19    | 5m       |
| 20    | 6m       |
| 21    | 7m       |
| 22    | 8m       |
| 23    | 9m       |
| 24    | 10m      |
| 25    | 11m      |
| 26    | 12m      |
| 27    | 13m      |
| 28    | 14m      |
| 29    | 15m      |
| 30    | 16m      |
| 255   | Invalid  |
