WITH dbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%'
    AND (LOWER(label) LIKE '%blood pressure%' OR LOWER(label) LIKE '%bp%')
),

-- Step 2: Get eligible female patients aged 71-81
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 71 AND 81
),

-- Step 3: Get ICU stays for eligible patients
eligible_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN eligible_patients p ON icu.subject_id = p.subject_id
),

-- Step 4: For each stay, get the maximum DBP
stay_max_dbp AS (
  SELECT
    s.stay_id,
    MAX(c.valuenum) AS max_dbp
  FROM eligible_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  INNER JOIN dbp_items d
    ON c.itemid = d.itemid
  WHERE c.valuenum IS NOT NULL
  GROUP BY s.stay_id
)

-- Step 5: Calculate the median of per-stay maximum DBP
SELECT
  APPROX_QUANTILES(max_dbp, 2)[OFFSET(1)] AS median_per_stay_max_dbp
FROM stay_max_dbp
WHERE max_dbp IS NOT NULL;