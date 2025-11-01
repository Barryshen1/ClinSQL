WITH
-- 1. Identify male patients age 53–63
cohort_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 53 AND 63
),

-- 2. Admissions of that cohort
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Compute LOS in days (inclusive)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    cohort_patients p
  USING(subject_id)
),

-- 3. Admissions with a diagnosis of heart failure (ICD-10)
hf_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    d.icd_version = 10
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),

-- 4. Precomputed Charlson scores placeholder
-- In a real workflow you'd derive this from all diagnoses_icd
charlson_scores AS (
  -- subject_id, hadm_id, charlson_index
  SELECT
    subject_id,
    hadm_id,
    /* placeholder logic */ 
    -- e.g. sum of weights per ICD
    0 AS charlson_index
  FROM
    hf_admissions
),

-- 5. Combine everything and restrict to HF cohort
base AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.los_days,
    ca.hospital_expire_flag,
    ca.discharge_location,
    -- LOS category
    CASE
      WHEN ca.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN ca.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '8+'
    END AS los_cat,
    -- Charlson category
    CASE
      WHEN cs.charlson_index <= 3 THEN '≤3'
      WHEN cs.charlson_index BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_cat
  FROM
    cohort_admissions ca
  JOIN
    hf_admissions hf
  USING(subject_id, hadm_id)
  LEFT JOIN
    charlson_scores cs
  USING(subject_id, hadm_id)
)

SELECT
  los_cat,
  charlson_cat,
  COUNT(*) AS n_admissions,
  100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS pct_mortality,
  AVG(los_days) AS avg_los,
  -- absolute difference in avg LOS vs LOS = '1-3'
  AVG(los_days) - 
    (SELECT AVG(los_days) FROM base WHERE los_cat = '1-3' AND charlson_cat = b.charlson_cat) 
    AS abs_diff_vs_1_3,
  -- relative difference: (this - ref)/ref
  (AVG(los_days) /
    NULLIF((SELECT AVG(los_days) FROM base WHERE los_cat = '1-3' AND charlson_cat = b.charlson_cat),0)
  - 1.0) * 100 AS pct_diff_vs_1_3,
  -- discharge destination percentages
  100.0 * SUM(CASE WHEN discharge_location = 'HOME'   THEN 1 ELSE 0 END) / COUNT(*) AS pct_home,
  100.0 * SUM(CASE WHEN discharge_location = 'REHAB'  THEN 1 ELSE 0 END) / COUNT(*) AS pct_rehab,
  100.0 * SUM(CASE WHEN discharge_location = 'SNF'    THEN 1 ELSE 0 END) / COUNT(*) AS pct_snf,
  100.0 * SUM(CASE WHEN discharge_location = 'HOSPICE' THEN 1 ELSE 0 END) / COUNT(*) AS pct_hospice
FROM
  base b
GROUP BY
  los_cat,
  charlson_cat
ORDER BY
  los_cat,
  charlson_cat;