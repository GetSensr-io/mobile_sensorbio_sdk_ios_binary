/*
 * Amiigo protocol definitions
 *
 * @date Oct 3, 2013
 * @author: dashesy
 */

#ifndef AMIDEFS_H
#define AMIDEFS_H

#if defined(__GNUC__) || defined(__clang__)
#ifndef TRUE
#define TRUE 1
#endif

#ifndef FALSE
#define FALSE 0
#endif
#include <stdint.h>

typedef int8_t int8;
typedef uint8_t uint8;
typedef int16_t int16;
typedef uint16_t uint16;
typedef int32_t int32;
typedef uint32_t uint32;
#if defined(__GNUC__)
#include <stdbool.h>
#endif

#define PACKED __attribute__((__packed__))
#else
#define PACKED
#endif

#ifdef __cplusplus
extern "C" {
#endif
    
    // Base UUID: CCA30000-78C6-4785-9E45-0887D451317C
#define AMI_UUID(uuid) \
0x7C, 0x31, 0x51, 0xD4, 0x87, 0x08, \
0x45, 0x9E, \
0x85, 0x47, \
0xC6, 0x78, \
LO_UINT16(uuid), HI_UINT16(uuid), \
0xA3, 0xCC
    
#define AMI_ID16(id) BUILD_UINT16(id[12], id[13])
    
#define AMI_UUID_SIZE ATT_UUID_SIZE
    
#define WED_UUID_SERVICE  0x1000
#define WED_UUID_STATUS   0x0001 // Data type: WEDStatus
#define WED_UUID_CONFIG   0x0002 // Data type: WEDConfig
#define WED_UUID_LOGDATA  0x0003 // Data type: WEDLog
#define WED_UUID_FIRMWARE 0x0004 // Data type: WEDFirmwareCommand/Status
#define WED_UUID_DEBUG    0x0005 // Data type: WEDDebug
#define WED_UUID_BUILD    0x0006 // Data type: String
#define WED_UUID_VERSION  0x0007 // Data type: WEDVersion
    
    // NOTE: Structs below are byte packed. Integers are little-endian.
    
    // # of ticks per second for timestamps
#define WED_TIME_TICKS_PER_SEC 128
    
#define WED_TAG_SIZE 4
    
#define PING_TIMEOUT_SEC 120 // App must send any command in this interval or the device will disconnect
    // Suggested App sends at rate 3 or 4 times faster than this.
    
    ///////////////////////////////////////////////////////////////////////////////
    // Version
    typedef struct {
        uint8 Major;
        uint8 Minor;
        uint16 Build;
    } PACKED WEDVersion;
    
    ///////////////////////////////////////////////////////////////////////////////
    // Status
    
#define STATUS_UPDATE        0x01
#define STATUS_STATE0        0x02
#define STATUS_CHARGING      0x04
#define STATUS_LS_INPROGRESS 0x08
#define STATUS_STATE1        0x10
#define STATUS_WORN          0x20
#define STATUS_RECORDING     0x40
#define STATUS_WRISTBAND     0x80
    
#define STATUS_MASK      (STATUS_STATE0 | STATUS_STATE1)
#define STATUS_MASK_DF   0             // 00 -> DF state
#define STATUS_MASK_FA   STATUS_STATE0 // 01 -> Custom state (not in "DF", Fallout, "SL") i.e. old FA mode
#define STATUS_MASK_SL   STATUS_STATE1 // 10 -> Sleep state "SL" (a custom state)
#define STATUS_MASK_FO   STATUS_MASK   // 11 -> Fallout state
    
    // Top-level struct for characteristic UUID AMI_UUID(WED_UUID_STATUS)
    typedef struct {
        // Total # of stored entries
        uint32 num_log_entries;
        
        // 0 to 100
        uint8 battery_level;
        
        // BIT FIELD
        // Bit 0: Is a firmware update in progress
        // Bit 1: bit0 of the mode (Use STATUS_MASK_* mask to find the state)
        // bit 2: Are we charging.
        // bit 3: LS collection in progress.
        // bit 4: bit1 of the mode (Use STATUS_MASK_* mask to find the state)
        // bit 5: if pox thinks the unit is worn
        // bit 6: if accel is being recorded
        // bit 7: set if this is wristband
        uint8 status;
        
        // firmware version encoded
        struct {
            uint16 reserved : 4;
            uint16 Major : 4;
            uint16 Minor : 4;
            uint16 Build : 4;
        } version;
        union {
            char mode[2];  // "SL": Sleep, ...
            uint16 state;  // This is aliased with mode, as an integer.
        };
        uint32 epoch; // Unix timestamp (seconds since epoch)
        
        // how many times has the system rebooted since the last power cycle, or maintance reset.
        uint8 reboot_count;
    } PACKED WEDStatus;
    
    
    typedef struct {
        uint16 reseved; // reserved, set to 0
        uint32 epoch;   // Unix timestamp (seconds since epoch)
    } PACKED WEDConfigStatus;
    
    ///////////////////////////////////////////////////////////////////////////////
    // Configuration
    
#define WED_RATE_SCALE 10
    
    // This is used to calculate the values for rate (This is not linear)
    // interval_msec is the data logging interval in milliseconds.
    // Max interval is 255 * WED_RATE_SCALE msec.
    // Min interval is 2 * WED_RATE_SCALE msec.
    // Setting the interval to 0 will disable logging for that parameter.
    static inline uint16 WEDConfigRateParam(uint32 interval_msec) {
        if (!interval_msec) return 0;
        uint32 tmp = (interval_msec-1) / WED_RATE_SCALE + 1; // round up
        if (tmp > 0xffff) tmp = 0xffff;
        return tmp;
    }
    
#define MODE_TO_STATE(mode) ((uint16)(mode[0]) | (((uint16)(mode[1])) << 8))
#define CFG_FLAG_FALLOUT         0x01  // Configure the Fallout state
#define CFG_FLAG_FLUSH           0x02  // Flush logs to storage after new rates are set
#define CFG_FLAG_LS_START_NOW    0x04  // Take pulse right away (manual)
#define CFG_FLAG_LS_ABORT        0x08  // Abort current pulse (if in progress)
#define CFG_FLAG_LS_POWER        0x10  // Power saving experimental mode
    
    typedef struct {
        union {
            char mode[2];  // "SL": Sleep, ...
            uint16 state;  // This is aliased with mode, as an integer.
        };
        uint8 accel_interval;  // Accel rate for this mode (milliseconds / WED_RATE_SCALE)
        uint8 temp_interval;   // Temperature rate for this mode (in 10s of seconds)
        uint16 ls_duration;    // Duration of capture for this mode (in seconds)
        uint16 ls_interval;    // Interval of Light Sensor captures in this mode (in seconds)
        uint8 movement;        // Average movement level at which starting a reading is still allowed
        uint8 gyro_interval;   // similar to accel_interval
    } PACKED State_t;
    
    typedef struct {
        uint16 flags;      // CFG_FLAG_*
        uint16 reserved;   // Reserved for absolute timeout, must set to 0
        uint16 timeout;    // Timeout (in seconds) to go to the Fallout mode. 0 for no timeout
        State_t state;     // System state
    } PACKED WEDConfigState;
    
    typedef struct {
        // Connection interval in 1.25ms units. Min 6, max 32.
        uint8 conn_intr;
        
        // Supervision timeout in 10ms units. Min 10, max 3200.
        uint16 timeout;
    } PACKED WEDConfigConn;
    
    typedef enum {
        WED_MAINT_RESET_CONFIG, // Reset config to defaults
        WED_MAINT_CLEAR_LOG,    // Clear data log
        WED_MAINT_RESET,        // Reset CPU
        WED_MAINT_TAG,          // Insert WEDLogTag entry into log
        WED_MAINT_BLINK_LED,    // blink USER
        WED_MAINT_SYSTEM_LED,   // Enable system LED
        WED_DEEP_SLEEP,         // turn off until hard double tap.
        WED_TEST_SEQUENCE,      // set test sequence command to on or off
        WED_MAINT_RF_TEST,      // Start Radio Test
        WED_MAINT_MFGR_TEST,    // Re-Start Mafufacturing test cycle.
        
    } PACKED WED_MAINT_CMD;
    
    typedef struct {
        // tag data for WEDLogTag entry
        uint8 tag[WED_TAG_SIZE];
    } PACKED WEDMaintTag;
    
    typedef struct {
        uint8 led;       // green = 1, red = 2, 4 = PulseOx RED LED
        uint8 speed;     // 1 - 3 in sec
        uint8 duration;  // how long to stay in this state in sec. 0 will cancel an existing duration.
    } PACKED WEDMaintLED;
    
    
    // This command will auto tetminate the connection before returning.
    // App will not be able to restablish the conection until the RF test has compleated.
    typedef struct {
        uint8 test;      // test number from 1 to 9
        uint8 duration;  // duration in counts for each full cycle of sequence
    } PACKED APPMaintRFTest;
    
    typedef struct {
        uint8 enable;       // set to non-zero to enable the on board system LED
    } PACKED WEDMMaintSystemLED;
    
    typedef struct {
        // WED_MAINT_CMD value
        uint8 command;
        
        union {
            WEDMaintTag tag;
            WEDMaintLED led;
            WEDMMaintSystemLED sysled;
            uint8 mode;
        };
    } PACKED WEDConfigMaint;
    
    enum {
        // Turns on automatic data log download via notifications
        WED_CONFIG_LOG_DL_EN  = (1 << 0),
        
        // Enables WED_LOG_ACCEL_CMP compressed format.
        // Log must be cleared when setting this from enabled to disabled.
        WED_CONFIG_LOG_CMP_EN   = (1 << 1),
        
        // Log Loopback, bypasses the flash storage.
        // used to save battery life if you stay connected to the phone
        WED_CONFIG_LOG_LOOPBACK = (1 << 2),
        
        // Enables WED_LOG_LS_DATA_CMP compressed format.
        // Log must be cleared when setting this from enabled to disabled.
        WED_CONFIG_LOG_LS_DATA_CMP_EN = (1 << 3),
    };
    
    typedef struct {
        // WED_CONFIG_LOG_xxx flags
        uint8 flags;
    } PACKED WEDConfigLog;
    
#define DEV_NAME_LEN 13
    
    typedef struct {
        // WED_CONFIG_NAME
        char name[DEV_NAME_LEN];
    } PACKED WEDConfigName;
    
    
    typedef enum {
        WED_CFG_GENERAL,  // Obsolete
        WED_CFG_ACCEL,    // Obsolete
        WED_CFG_LS,       // Obsolete
        WED_CFG_NOTHING,  // Reserved
        WED_CFG_TEMP,     // Obsolete
        WED_CFG_MAINT,
        WED_CFG_LOG,
        WED_CFG_CONN,
        WED_CFG_NAME,
        WED_CFG_STATE,
    } WED_CFG_TYPE;
    
    // Top-level struct for characteristic UUID AMI_UUID(WED_UUID_CONFIG)
    typedef struct {
        // WED_CFG_TYPE identifying following struct type
        uint8 config_type;
        
        // Structure corresponding to config_type
        union {
            WEDConfigState state;
            WEDConfigMaint maint;
            WEDConfigLog log;
            WEDConfigConn conn;
            WEDConfigName name;
        };
    } PACKED WEDConfig;
    
    ///////////////////////////////////////////////////////////////////////////////
    // Data Log
    
    // Characteristic UUID AMI_UUID(WED_UUID_LOGDATA) will return zero or
    // more of the following structs (depending on how many will fit in
    // the BLE stack's buffer and how many log entries are left). Each
    // struct holds the data for a single log entry. The first byte of
    // each struct is a 'type' byte from the WED_LOG_TYPE enum that
    // identifies the type of the structure. If multiple entries are
    // present, they will be packed back-to-back in the data block. Log
    // entries are erased as they are read. To read the whole log,
    // continue reading this characteristic until
    // WEDStatus.num_log_entries have been read.
    
    // When log download is enabled in WEDConfigLog, notifications will be
    // sent automatically when log data is available. The notification
    // data will be in the same format as reading this characteristic,
    // except that the upper 4 bits of the first byte of each packet will
    // be overwritten with a rolling sequence number. The sequence number
    // should be used to check for missing or out-of-order packets.
    
    // CNBC: As of 10-3-13 the sequence number has been removed
    // 5 bits are reserved for the type value
    // 3 bits are reserved as type specfic meta data
    
    typedef enum {
        WED_LOG_MILESTONE2 = 0, // For TDK, WED_LOG_TIME
        WED_LOG_ACCEL = 1,
        WED_LOG_LS_CONFIG = 2,
        WED_LOG_LS_DATA = 3,
        WED_LOG_TEMP = 4,
        WED_LOG_TAG = 5,
        WED_LOG_ACCEL_CMP = 6,
        WED_LOG_COUNT = 7,
        WED_LOG_EVENT = 8,
        WED_LOG_STATE = 9,
		WED_LOG_IMU = 10,
		WED_LOG_IMU_CMP = 11,
		WED_LOG_GYRO = 12,
		WED_LOG_LS_INFO = 16,
		WED_LOG_DETAILED_ACCEL = 17,
		WED_LOG_DETAILED_GYRO = 18,
		WED_LOG_DETAILED_IMU = 19,
		WED_LOG_IMU_SAMPLE_COUNT = 52
    } WED_LOG_TYPE;
    
#define WED_TAG_BITS 0x1F
    
    // Timestamp records indicate the timestamp of the log entry immediately following it.
    // They will be inserted periodically, or any time the state changes.
    
#define TIMESTAMP_REBOOTED  0x80
#define TIMESTAMP_DBG       0x10
    
    typedef struct {
        uint8 type; // WED_LOG_TIME
        
        // Timestamp for next log entry, in WED_TIME_TICKS_PER_SEC
        uint32 timestamp;
        
        uint8 flags;
    } PACKED WEDLogTimestamp;
	
	typedef struct {
		uint8 type; // WED_LOG_IMU_SAMPLE_COUNT
		
		uint8 samples;
		uint16 milliseconds;
	} PACKED WEDLogIMUSampleCount;
    
    typedef struct {
        uint8 type; // WED_LOG_ACCEL
        
        // Accelerometer values directly from the MMA8451Q OUT_X/Y/Z_MSB registers.
        int8 accel[3];
    } PACKED WEDLogAccel;
	
	typedef struct {
		uint8 type; // WED_LOG_GYRO
		
		// Gyroscope values directly from the MMA8451Q OUT_X/Y/Z_MSB registers.
		int8 gyro[3];
	} PACKED WEDLogGyro;
	
	typedef struct {
		uint8 type; // WED_LOG_DETAILED_ACCEL
		
		// Accelerometer values directly from the MMA8451Q OUT_X/Y/Z_MSB registers.
		int16 accel[3];
	} PACKED WEDLogDetailedAccel;
	
	typedef struct {
		uint8 type; // WED_LOG_DETAILED_GYRO
		
		// Gyroscope values directly from the MMA8451Q OUT_X/Y/Z_MSB registers.
		int16 gyro[3];
	} PACKED WEDLogDetailedGyro;
    
    enum {
        WED_LOG_ACCEL_CMP_3_BIT,
        WED_LOG_ACCEL_CMP_4_BIT,
        WED_LOG_ACCEL_CMP_5_BIT,
        WED_LOG_ACCEL_CMP_6_BIT,
        WED_LOG_ACCEL_CMP_8_BIT,
        WED_LOG_ACCEL_CMP_STILL,  // NO DATA FOLLOWS
    };
    
    typedef struct {
        uint8 type; // WED_LOG_ACCEL_CMP
        
        // Bits 3-0: Number of samples - 1 in this log entry (e.g. 0=1 sample, 15=16 samples).
        // Bits 6-4: Data size, one of WED_LOG_ACCEL_CMP_x_BIT
        // Bit 7: count only. If set there is no data. All data in the count of samples was the same or within the acceptable noise level.
        uint8 count_bits;
        
        // For WED_LOG_ACCEL_CMP_8_BIT, the following samples are normal
        // 8-bit values. For the 3/4/5/6_BIT types, values are deltas of the
        // specified size. The delta is based on the previous sample, which
        // may have come in a regular WEDLogAccel entry. The deltas are
        // tracked per-axis (e.g. the Y1 delta is Y1 - Y0, not Y1 - X1).
        // Values are packed starting from the high bit of the first
        // byte. The ordering is X0, Y0, Z0, X1, Y1, Z1, etc.
        uint8 data[0];
    } PACKED WEDLogAccelCmp;
    
    // Returns the size of a WEDLogAccelCmp entry.
    static inline uint8 WEDLogAccelCmpSize(void* buf) {
        
        WEDLogAccelCmp* pkt = buf;
        
        uint8 bps;
        switch ((pkt->count_bits >> 4) & 0x7) {
            case WED_LOG_ACCEL_CMP_3_BIT: bps = 3*3; break;
            case WED_LOG_ACCEL_CMP_4_BIT: bps = 4*3; break;
            case WED_LOG_ACCEL_CMP_5_BIT: bps = 5*3; break;
            case WED_LOG_ACCEL_CMP_6_BIT: bps = 6*3; break;
            case WED_LOG_ACCEL_CMP_8_BIT: bps = 8*3; break;
            case WED_LOG_ACCEL_CMP_STILL: return 2;
            default: return 0;
        }
        
        uint16 bits = ((pkt->count_bits & 0xf) + 1) * bps;
        if (bits > 144)
            return 0;
        
        return 2 + ((uint8)bits - 1) / 8 + 1;
    }
    
#define LSCONF_LAST      0xFF // Last log (all data will be 0xFF)
#define LSCONF_LED_MASK  0x70 // config led number
    
#define LSCONF_FLAGS_MANUAL 0x01 // If this is a manual capture
#define LSCONF_FLAGS_WORN   0x02 // If last know state is worn
    
    // This is generated once at the beginning and end of each interval.
    typedef struct {
        uint8 type; // WED_LOG_LS_CONFIG
        
        uint8 dac_on;    // DAC setting for led
        uint8 flags;     // LSCONF_FLAGS_*
        uint8 level_led; // LED driver setting for led
        uint8 gain;      // calibrated gain value for led
        uint8 log_size;  // log state bifield LSCONF_*
    } PACKED WEDLogLSConfig;
    
    // This is generated once for each red/IR/off sample group.
    typedef struct {
        uint8 type; // WED_LOG_LS_DATA
        
        // A/D readings. There will be 1-3 values present depending on how
        // many readings were enabled in WEDConfigLS.leds. The order is red,
        // IR, off, excluding readings that aren't enabled.
        
        // The upper 3 bits of the type will determine how long the log entry is.
        // bit 5: is set if we have RED data
        // bit 6: is set if we have IR data
        // bit 7: is set if we have OFF data
        uint16 val[3];
    } PACKED WEDLogLSData;
	
	typedef struct {
		uint8 type;				// wvLogPacketTypeLSIROnlyData
		uint16 ir;				// IR Data
	} PACKED wvLSIROnlyData;
	
	typedef struct {
		uint8 type;				// wvLogPacketTypeLSRedIROnlyData
		uint16 red;				// Red Data
		uint16 ir;				// IR Data
	} PACKED wvLSIRRedOnlyData;
	
	typedef struct {
		uint8_t type;			// wvLogPacketTypeLSRedIRData
		uint32_t timestamp;		// 32-bit microsecond timestamp offset from start of light sensor capture
		uint16_t red;			// Red Data
		uint16_t ir;			// IR Data
	} PACKED wvLSTSIRRedData;
	
	typedef struct {
		uint8_t type;			// wvLogPacketTypeLSRedIRData
		uint32_t timestamp;		// 32-bit microsecond timestamp offset from start of light sensor capture
		uint16_t ir;			// IR Data
	} PACKED wvLSTSIRData;
    
    // Returns the size of a WEDLogLSData entry.
    static inline uint8 WEDLogLSDataSize(void* buf) {
        return sizeof(uint8) + (sizeof(uint16) * (
                                                  ((((WEDLogLSData*)buf)->type & 0x80) ? 1 : 0) +
                                                  ((((WEDLogLSData*)buf)->type & 0x40) ? 1 : 0) +
                                                  ((((WEDLogLSData*)buf)->type & 0x20) ? 1 : 0)
                                                  ));
    }
	
	// This is generated once for each red/IR/off sample group.
	typedef struct {
		uint8 type; // WED_LOG_LS_INFO
		
		uint8 info_type;	// Type of lightsensor info. Integer mapping to external list.
		uint16 val;			// 16-bit value for info.
	} PACKED WEDLogLSInfo;
	
    typedef struct {
        uint8 type; // WED_LOG_TEMP
		
        int16 temperature;  // DegC * 10
    } PACKED WEDLogTemp;
    
    // This is generated when a WED_MAINT_TAG command is issued.
	// TDK hardware only.
    typedef struct {
        uint8 type; // WED_LOG_TAG
        
        // Tag data from WED_MAINT_TAG command
        uint8 tag[WED_TAG_SIZE];
    } PACKED WEDLogTag;
	
	// CYPRESS 1.4.x firmware diagnostic packets
	typedef struct {
		uint8 type;				// wvLogPacketTypeDiagnostic (0x05)
		uint8 size;				// Accounts for this byte plus the following bytes
		uint8 diag_type;		// wvDiagnosticPacketTypeWornCheck (0x00)
		uint8 phase;			// Phase of the worn check
		uint16 darkWornValue;	// Worn value "passive" (no LED)
		uint16 irWornValue;		// Worn value after IR
		uint16 darkWornOffset;
		uint16 irWornOffset;
	} PACKED wvDiagnosticPacketWornCheck;
	
	typedef struct {
		uint8 type;				// wvLogPacketTypeDiagnostic (0x05)
		uint8 size;				// Accounts for this byte plus the following bytes
		uint8 diag_type;		// wvDiagnosticPacketTypeBattery (0x01)
		uint8 percentage;
	} PACKED wvDiagnosticPacketBattery;
    
    // This LOG entry is placed into the log on a reboot after a scan is done.
	// This is an old TDK-only packet type, replaced by the wvLSIRRedOnlyData type in Cypress.
    typedef struct {
        uint8 type; // WED_LOG_COUNT
        uint32 log_timestamp;   // Last logged timestamp before reboot
        uint16 log_accel_count; // Last number of accel logs since log_timestamp before reboot
        uint32 old_timestamp;   // Last known timestamp before reboot
        uint32 timestamp;       // ticks since reboot until log is ready
    } PACKED WEDLogCount;
    
#define EVENT_FLAGS_FN         0x03 // 4 functionalities 00:tap-fall
#define EVENT_FLAGS_TAP_D      0x04 // double-tap
#define EVENT_FLAGS_TAP_X      0x08 // x
#define EVENT_FLAGS_TAP_Z      0x10 // z
#define EVENT_FLAGS_TAP_ZD     (EVENT_FLAGS_TAP_D | EVENT_FLAGS_TAP_Z)
#define EVENT_FLAGS_TAP_XD     (EVENT_FLAGS_TAP_D | EVENT_FLAGS_TAP_X)
#define EVENT_FLAGS_TAP_MASK   (EVENT_FLAGS_TAP_D | EVENT_FLAGS_TAP_Z | EVENT_FLAGS_TAP_X)
#define EVENT_FLAGS_FALL       0x20
    
    
    typedef struct {
        uint8 type;     // WED_LOG_EVENT
        uint8 flags;    // EVENT_FLAGS_*
    } PACKED WEDLogEvent;
    
    typedef struct {
        uint8 type;        // WED_LOG_STATE
        uint32 epoch;      // Unix timestamp (seconds since epoch)
        State_t state;     // System state
    } PACKED WEDLogState;
	
	typedef struct {
		uint8			type;			// wvLogPacketTypeMilestoneNew
		uint32			epoch;			// Unix timestamp (seconds since epoch)
		
		union {
			char		mode[2];		// "SL": Sleep, ...
			uint16		state;			// This is aliased with mode, as an integer.
		};
		
		uint8			imuInterval;	// Accel/Gyro rate for this mode (milliseconds / WED_RATE_SCALE)
		uint8			system1;		// System byte 1
		uint16			lsDuration;		// Duration of capture for this mode (in seconds)
		uint16			lsInterval;		// Interval of Light Sensor captures in this mode (in seconds)
		uint8			system2;		// System byte 2
		uint8			system0;		// System byte 0
		uint8			system3;		// System byte 3
		uint8			system4;		// System byte 4
	} PACKED wvLogMilestoneNewStruct;
	
	typedef struct {
		uint8 			type;
		uint16			flags;
		uint8			accelRange;
		uint8			gyroRange;
		uint8			reserved[12];
	} PACKED wvLogMilestoneMoreStruct;
	
    ///////////////////////////////////////////////////////////////////////////////
    // Firmware Update
    
    typedef enum {
        WED_FIRMWARE_INIT,
        WED_FIRMWARE_DATA_BLOCK,
        WED_FIRMWARE_DATA_DONE,
        WED_FIRMWARE_UPDATE,
    } WED_FIRMWARE_TYPE;
    
#define WED_FW_HEADER_SIZE 16
#define WED_FW_BLOCK_SIZE 16
#define WED_FW_STREAM_BLOCKS 16
    
    // Top-level struct for writing characteristic UUID AMI_UUID(WED_UUID_FIRMWARE)
    typedef struct {
        // WED_FIRMWARE_TYPE identifying following struct type
        uint8 pkt_type;
        
        // Structure corresponding to config_type
        union {
            uint8 header[WED_FW_HEADER_SIZE];
            uint8 data[WED_FW_BLOCK_SIZE];
        };
    } PACKED WEDFirmwareCommand;
    
    // Returned when writing a firmware command in an invalid state
#define FW_ERR_INVALID_STATE 0x81
    
    typedef enum {
        WED_FWSTATUS_IDLE,         // No firmware update is in progress
        WED_FWSTATUS_WAIT,         // Processing, continue polling status
        WED_FWSTATUS_UPLOAD_READY, // Ready for data upload
        WED_FWSTATUS_UPDATE_READY, // Ready to update flash
        WED_FWSTATUS_ERROR,        // Error, update aborted
    } WED_FIRMWARE_STATUS;
    
    typedef enum {
        WED_FWERROR_NONE,    // No error
        WED_FWERROR_HEADER,  // Firmware image header was unrecognized
        WED_FWERROR_SIZE,    // Image size was too large
        WED_FWERROR_CRC,     // CRC check failed
        WED_FWERROR_FLASH,   // SPI flash error
        WED_FWERROR_OTHER,   // Internal error
    } WED_FIRMWARE_ERROR;
    
    // Top-level struct for reading characteristic UUID AMI_UUID(WED_UUID_FIRMWARE)
    typedef struct {
        // WED_FIRMWARE_STATUS value
        uint8 status;
        
        // WED_FIRMWARE_ERROR value, valid if status is WED_FWSTATUS_ERROR
        uint8 error_code;
    } PACKED WEDFirmwareStatus;
    
    // Pseudocode for Firmware Update Procedure
    //
    // Once the WED_FIRMWARE_INIT command is sent, the unit will stop
    // logging and all other operations not necessary to complete the
    // update. To abort the update and return to normal operation, send
    // the WED_MAINT_RESET command.
    
#if 0
    update() {
        WEDFirmwareCommand init = { WED_FIRMWARE_INIT	};
        read(firmware_file, init.header, WED_FW_HEADER_SIZE);
        
        ble_write(WED_UUID_FIRMWARE, init);
        
        seek_to_beginning(firmware_file);
        while (!end_of_file(firmware_file)) {
            WEDFirmwareStatus status = {0};
            ble_read(WED_UUID_FIRMWARE, status);
            
            if (status.status == WED_FWSTATUS_WAIT)
                continue;
            
            if (status.status != WED_FWSTATUS_UPLOAD_READY)
                return ERROR;
            
            for (int i = 0; i < WED_FW_STREAM_BLOCKS; i++) {
                WEDFirmwareCommand data = { WED_FIRMWARE_DATA_BLOCK };
                read(firmware_file, data.data, WED_FW_BLOCK_SIZE);
                ble_write(WED_UUID_FIRMWARE, data);
            }
        }
        
        WEDFirmwareCommand done = { WED_FIRMWARE_DATA_DONE };
        ble_write(WED_UUID_FIRMWARE, done);
        
        while (1) {
            WEDFirmwareStatus status = {0};
            ble_read(WED_UUID_FIRMWARE, status);
            
            if (status.status == WED_FWSTATUS_WAIT)
                continue;
            
            if (status.status != WED_FWSTATUS_UPDATE_READY)
                return ERROR;
        }
        
        WEDFirmwareCommand update = { WED_FIRMWARE_UPDATE };
        ble_write(WED_UUID_FIRMWARE, update);
        
        // The device will now go offline for a while to complete the update.
    }
#endif
    
    ///////////////////////////////////////////////////////////////////////////////
    // DEBUG, Direct access to all I2C recisters.
    
    typedef struct {
        uint8 address; // I2C Address
        uint8 reg;     // I2C Register
        uint8 write;   // in non-zero this is a write, else it's a read
        uint8 data;    // must be valid of if write is non-zero
    } PACKED WEDDebugI2CCmd;
    
    typedef struct {
        uint8 status; // status of command. 0 for no errors
        uint8 data;   // value of last good read.
    } PACKED WEDDebugI2CResult;
    
    typedef struct {
        uint8 cmd; // 1 to force the 2.7V regulator on
    } PACKED WEDDebug27V;
    
    typedef struct {
        uint8 level[2]; // Max levels for LED (RED, IR)
        uint8 max_gain[2];  // Max gains for LED (RED, IR)
        uint8 debug; // Pox debug verbosity
    } PACKED WEDDebugPox;
    
    typedef enum {
        WED_DBG_I2C,
        WED_DBG_27V,
        WED_DBG_POX,
    } PACKED WED_DBG_TYPE;
    
    // Top-level struct for characteristic UUID AMI_UUID(WED_UUID_CONFIG)
    typedef struct {
        // WED_DBG_TYPE identifying following struct type
        uint8 debug_type;
        
        // Structure corresponding to config_type
        union {
            WEDDebugI2CCmd i2ccmd;
            WEDDebug27V reg27v;
            WEDDebugPox pulse;
        };
    } PACKED WEDDebug;
    
    
#ifdef __cplusplus
}
#endif

#endif // include guard
