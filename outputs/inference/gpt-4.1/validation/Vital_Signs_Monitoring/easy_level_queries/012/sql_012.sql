WITH diastolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%'
    AND (LOWER(label) LIKE '%bp%' OR LOWER(label) LIKE '%blood pressure%')
),

-- Step 2: Get eligible ICU stays for male patients age 49-59 in step-down/IMC
eligible_stays AS (
  SELECT DISTINCT icu.stay_id, icu.subject_id, icu.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.transfers` tr
    ON icu.hadm_id = tr.hadm_id
    AND icu.subject_id = tr.subject_id
    AND tr.careunit IN ('STEPDOWN', 'IMC')
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
),

-- Step 3: Calculate mean diastolic BP per stay
mean_diastolic_bp_per_stay AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_diastolic_bp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN diastolic_bp_items di
    ON ce.itemid = di.itemid
  JOIN eligible_stays es
    ON ce.stay_id = es.stay_id
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
)

-- Step 4: Calculate IQR of mean diastolic BP per stay
SELECT
  APPROX_QUANTILES(mean_diastolic_bp, 4)[OFFSET(1)] AS iqr_25th_percentile,
  APPROX_QUANTILES(mean_diastolic_bp, 4)[OFFSET(3)] AS iqr_75th_percentile
FROM mean_diastolic_bp_per_stay;