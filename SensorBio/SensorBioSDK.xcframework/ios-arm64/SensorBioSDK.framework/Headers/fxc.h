/**
* \addtogroup Philips WeST Software Library
* \{
*/

/**
*  \file    fxc.h
*  \author  Philips Intellectual Property & Standards, The Netherlands
*  \brief   WeST Sleep Library
*
*  \remarks (c) Copyright 2018 Koninklijke Philips N.V. All rights reserved.
*  This Software Library is provided to Biostrap USA, LLC. for use under and subject to the terms of the Evaluation License Agreement dated 22 May 2023.
*  Philips Sensing Platform, Philips and its logo are trademarks of Koninklijke Philips N.V..
*  All other names are the trademark or registered trademarks of their respective holders.
*/

/*============================================================================*/
/*  Multiple inclusion protection                                             */
/*============================================================================*/

#ifndef __FXC_H__
#define __FXC_H__

/*============================================================================*/
/*  C++ protection                                                            */
/*============================================================================*/

#ifdef __cplusplus
extern "C" {
#endif

/*============================================================================*/
/*  Include files                                                             */
/*============================================================================*/

#include "fx_datatypes.h"

/* input metrics */
#define FXC_METRIC_ID_WESTPRIVATEDATA          ( 0x2F )

/* extracted metrics */
#define FXC_METRIC_ID_SLEEPSESSION             ( 0x30 )

/** @defgroup FXC_ERROR FXC_ERROR 
 *  @{ */
#define FXC_ERROR_NONE                  ( 0x0000 ) /**< @brief no error */
#define FXC_ERROR_INVALID_PARAMS        ( 0xFF01 ) /**< @brief Provided parameters invalid */
#define FXC_ERROR_NO_MEMORY             ( 0xFF02 ) /**< @brief Not enough memory available withing FXC */
#define FXC_ERROR_INITIALISATION_FAILED ( 0xFF02 ) /**< @brief An error occurred during the initialization process */
#define FXC_ERROR_RETRIEVE_DATA         ( 0xFF03 ) /**< @brief Error retrieving data from FXC */
/** @} */

#define FXC_MAX_UPDATED_METRICS                ( 1 )
#define FXC_MAX_REQUIRED_METRICS               ( 1 )

/*============================================================================*/
/* Type definitions                                                           */
/*============================================================================*/
typedef FX_UINT16         FXC_ERROR;
typedef FX_UINT08         FXC_METRIC_ID;

/** @brief   FXC Instance Parameter structure type. */
typedef struct fxc_inst_params_tag
{
    FX_UINT08   *   pMem; /**< Pointer to the memory containing instance information */
    FX_UINT32       memorySize; /**< Size in bytes of the memory made available by caller */
} FXC_INST_PARAMS, * PFXC_INST_PARAMS;

typedef struct fxc_inst_tag * PFXC_INST;

/* Making/using this as a dynamic library ------------------------------------*/

#ifdef FXC_DYNAMIC_BUILD
    #ifdef FXC_BUILD
    #define FXC_API FX_INTF_EXPORT
    #else
    #define FXC_API FX_INTF_IMPORT
    #endif /* FXC_BUILD */

#else
    #define FXC_API  extern
#endif

/*============================================================================*/
/* Extern data declarations                                                   */
/*============================================================================*/

/*============================================================================*/
/*  External function prototypes                                              */
/*============================================================================*/

/*----------------------------------------------------------------------------*/
/**
 *  @brief        FXC_GetVersionInfo
 *
 *                Fills a byte array, appointed by pData, with version information
 *                that is unique for each version of the library.
 *                The array has to be allocated/maintained by the application.
 *
 *  @param        [in]  pData : Pointer to 'empty' byte array where the version information will be written to.
 *  @param        [in]  pSize : Length of the array, must be at least 20
 *
 *  @param        [out] pData : Pointer to 'filled' version array
 *  @param        [out] pSize : Length of the filled array
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note
 *
**/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_GetVersionInfo
(
    FX_UINT08 * const pData,
    FX_UINT16 * const pSize
);

/*----------------------------------------------------------------------------*/
/**
 *  @brief        FXC_GetDefaultParams
 *
 *                Fills a structure, appointed by pParams, with default data,
 *                e.g. minimal size of provided memory block,  to be used in function FXC_Initialise
 *
 *  @param        [in] pParams : Pointer to 'empty' parameter struct to be filled with default data
 *
 *  @param        [out] pParams: Filled FXC instance parameter. Default parameters filled, default size filled.
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note
 *
**/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_GetDefaultParams
(
        PFXC_INST_PARAMS const pParams
);

/*----------------------------------------------------------------------------*/
/**
 *  @brief        FXC_Initialise
 *
 *                Creates an @c FXC instance. Initialises the resources needed using the data
 *                  provided in the @c pParams structure. The actual used block of memory
 *                  (pointed to by the @p pParams->pMem pointer) must be maintained and not
 *                  modified during the lifetime of the instance.
 *
 *                On successful return, @p ppInst identifies the created FXC instance.
 *                  This pointer must be used in subsequent calls to functions relating to this instance.
 *
 *  @param        [in] pParams  : Pointer to a structure that contains parameters used for initializing the FXC instance.
 *  @param        [in] ppInst   : Pointer to an FXC instance pointer.
 *
 *  @param        [out] ppInst  : On success, a valid pointer to an FXC instance pointer.
 *  @param        [out] pParams : Pointer to a structure that contains updated information in the created instance
 *                                  ( e.g. actual memory used from the memory pool )
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note         The instance can be persisted by persisting the block of memory.
**/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_Initialise
( 
  FXC_INST_PARAMS       * const pParams,
  PFXC_INST             * const ppInst
);

/*----------------------------------------------------------------------------*/
/**
 *  @brief        FXC_Terminate
 *
 *                Cleans up and frees all resources used by the instance.
 *                pInst is <b>NO</b> longer usable after calling this function and
 *                  can be released by the application.
 *
 *  @param        [in]  ppInst : Pointer to an FXC instance pointer.
 *
 *  @param        [out] ppInst : On success, pointer to FXC instance pointer is set to NULL.
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note         
**/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_Terminate
(
  PFXC_INST             * const ppInst 
);

/*----------------------------------------------------------------------------*/
/**
 *
 *  @brief        FXC_ListRequiredMetrics
 *
 *                Returns an array of input metrics which FXC requires. Each value represents a metric ID.
 *                This list can dynamically change after FXC_Process() function
 *
 *  @param        [in]  pInst            : Pointer to an FXC instance.
 *  @param        [in]  pMetricIdList    : 'empty' list of metricId.
 *  @param        [in]  pNumberOfMetrics : maximum lenght of the metricId list.
 *  @param        [out] pMetricIdList    : filled list of metricId.
 *  @param        [out] pNumberOfMetrics : number of metricId in the filled list
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note
 *
 **/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_ListRequiredMetrics
(
  PFXC_INST       const pInst,
  FXC_METRIC_ID * const pMetricIdList,
  FX_UINT08     * const pNumberOfMetrics
);

/*----------------------------------------------------------------------------*/
/**
 *  @brief        FXC_SetMetric
 *
 *                Sets a metric value of the person represented by the FXC instance.
 *
 *  @param        [in] pInst  : Pointer to an FXC instance.
 *  @param        [in] pData  : Pointer to the metric data.
 *  @param        [in] size   : The size of the metric data.
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note         A single metric is passed into FXC: I.e a single WPD package in the format as received from FXI.
**/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_SetMetric
( 
  PFXC_INST           const pInst,
  FX_UINT08  const  * const pData,
  FX_UINT32           const size
);

/*----------------------------------------------------------------------------*/
/**
 *  @brief        FXC_Process
 *
 *                Extract output metrics from the person's input metrics provided with \ref FXC_SetMetric().<br>
 *                After processing, a list of updated output metrics is gotten with \ref FXC_ListUpdatedMetrics().<br>
 *                Updated output metrics are gotten with \ref FXC_GetMetric().<br>
 *
 *  @param        [in] pInst  : Pointer to an FXC instance.
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note         
**/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_Process
(
  PFXC_INST   const pInst
);

/*----------------------------------------------------------------------------*/
/**
 *
 *  @brief        FXC_ListUpdatedMetrics
 *
 *                Gets an array of updated output metrics, extracted with \ref FXC_Process().<br>
 *                If no metrics have been updated, an array of length 0 is returned.<br>
 *                <p>
 *                The listed metrics are gotten with \ref FXC_GetMetric().
 *
 *  @param        [in]  pInst            : Pointer to an FXC instance.
 *  @param        [in]  pMetricIdList    : 'empty' list of metricIds.
 *  @param        [in]  pNumberOfMetrics : maximum length of metricId list, maximal FXC_MAX_UPDATED_METRICS.
 *
 *  @param        [out] pMetricIdList    : filled list of metricId.
 *  @param        [out] pNumberOfMetrics : number of metricIds filled in list
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note
 **/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_ListUpdatedMetrics
(
  PFXC_INST       const pInst,
  FXC_METRIC_ID * const pMetricIdList,
  FX_UINT08     * const pNumberOfMetrics
);

/*----------------------------------------------------------------------------*/
/**
 *
 *  @brief        FXC_GetMetric
 *
 *                Returns the output metric(s) (\ref FXC_ListUpdatedMetrics()) resulting from the FXC_Process()
 *
 *  @param        [in]  pInst       : Pointer to an FXC instance.
 *  @param        [in]  metricId    : The single output metric type to be retrieved.
 *  @param        [in]  pData       : Pointer to location where metric data will be written to.
 *  @param        [in]  pSize       : The size in <b>bytes</b> of the memory allocated for the output metric data.
 *
 *  @param        [out] pData       : Pointer to the start of the filled metric data.
 *  @param        [out] pSize       : The size in <b>bytes</b> written into pData (metric data ).
 *
 *  @return       Value of type \ref FXC_ERROR identifying the error ( \ref FXC_ERROR_NONE if successful )
 *
 *  @note         The metric data consists of metricId,length,index,quality,data
 **/
/*----------------------------------------------------------------------------*/
FXC_API FXC_ERROR FXC_GetMetric
(
  PFXC_INST          const pInst,
  FXC_METRIC_ID      const metricId,
  FX_UINT08        * const pData,
  FX_UINT32        * const pSize
);

/*============================================================================*/
/*  End of C++ protection                                                     */
/*============================================================================*/

#ifdef __cplusplus
}
#endif

/*============================================================================*/
/*  End of multiple inclusion protection                                      */
/*============================================================================*/

#endif

/**
* \}
* End of file.
*/

