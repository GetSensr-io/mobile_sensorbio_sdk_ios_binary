#ifndef MATH_H
#define MATH_H

#include "common.h"
#include "bioedge_api.h"

#ifndef CONST_PI
#define CONST_PI (3.14159265358979323846)
#endif

#ifndef CONST_2PI
#define CONST_2PI (float)(3.14159265358979323846*2.0)
#endif

#ifndef CONST_2PI_INV
#define CONST_2PI_INV (float)(1.0/(3.14159265358979323846*2.0))
#endif


typedef struct{
    float 	*coefficients;
    float 	intercept;
    uint8_t order;
}logisticRegressionModel_s;

float safeDivide(float number1, float number2);
bioedge_ret_e MATH_interpolateUs(uint32_t x1, uint32_t x2, float y1, float y2, uint32_t xInterpolate, float *yInterpolate);
bioedge_ret_e MATH_sqrtf(const float in, float *out);
bioedge_ret_e MATH_vectorNormaliseOneAxis(float *arr, uint8_t arrLenght, uint8_t axisToReturn, float *normalisedAxis);
float MATH_applyLogisticRegressionModel(logisticRegressionModel_s model, float *data);
void MATH_parabolInterpolation(float *y, float *xinterp, float *yinterp);
void MAT_histogramF(const float *inputArray, int inputSize, float *bins, int *binCount, int numberOfBins);
float MAT_calculateStandardDeviation(float *arr, uint32_t size);
void MATH_lombscarglePeriodogram(double *x, double *y, double *freqs, double *lombOutput, int dataLength, int numberOfBins);
double MATH_compositeTrapezoidal(double *x, double *y, uint32_t startPos, uint32_t endPos);

#endif
