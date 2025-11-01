WITH eligible_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47
),

-- Step 2: Find stays with NIV events (CPAP/BiPAP)
niv_stays AS (
  SELECT DISTINCT
    es.stay_id
  FROM
    eligible_stays es
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON es.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (227187, 227188, 227189) -- CPAP/BiPAP/Resp Rate (CPAP)
    OR LOWER(ce.value) LIKE '%cpap%'
    OR LOWER(ce.value) LIKE '%bipap%'
),

-- Step 3: Get diastolic BP measurements for those stays
diastolic_bp AS (
  SELECT
    es.stay_id,
    ce.valuenum
  FROM
    eligible_stays es
    JOIN niv_stays ns
      ON es.stay_id = ns.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON es.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (220051, 220180) -- Non Invasive & Invasive Diastolic BP
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),

-- Step 4: Compute max diastolic BP per stay
max_diastolic_bp_per_stay AS (
  SELECT
    stay_id,
    MAX(valuenum) AS max_diastolic_bp
  FROM
    diastolic_bp
  GROUP BY
    stay_id
)

-- Step 5: Calculate 25th percentile
SELECT
  APPROX_QUANTILES(max_diastolic_bp, 4)[OFFSET(1)] AS diastolic_bp_25th_percentile
FROM
  max_diastolic_bp_per_stay
WHERE
  max_diastolic_bp IS NOT NULL;