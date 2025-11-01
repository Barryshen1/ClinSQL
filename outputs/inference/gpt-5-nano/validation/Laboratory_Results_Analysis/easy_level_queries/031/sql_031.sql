WITH icustay_pairs AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Step 2: collect all serum potassium lab values drawn on hospital discharge day
potassium_labs AS (
  SELECT le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON le.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON le.subject_id = pat.subject_id
  JOIN icustay_pairs AS icu
    ON icu.subject_id = le.subject_id
   AND icu.hadm_id = le.hadm_id
  WHERE LOWER(pat.gender) = 'm'
    -- potassium, serum
    AND LOWER(dli.label) LIKE '%potassium%'
    AND LOWER(dli.fluid) LIKE '%serum%'
    -- on discharge day
    AND DATE(le.charttime) = DATE(adm.dischtime)
    -- non-null numeric values
    AND le.valuenum IS NOT NULL
)

-- Step 3: compute the 75th percentile
SELECT CAST(quantiles[OFFSET(75)] AS FLOAT64) AS potassium_p75_discharge_day
FROM (
  SELECT APPROX_QUANTILES(valuenum, 100) AS quantiles
  FROM potassium_labs
) q;