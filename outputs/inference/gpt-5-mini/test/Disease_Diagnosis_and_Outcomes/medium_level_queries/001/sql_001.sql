WITH
-- 1) Admissions with patient info and primary diagnosis filtered for heart failure
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- LOS in days (whole days between admit and discharge)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- primary diagnosis (seq_num = 1) indicating heart failure (ICD-9 428*, ICD-10 I50*, or text)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dprim
    ON a.hadm_id = dprim.hadm_id AND dprim.seq_num = 1
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON TRIM(UPPER(dprim.icd_code)) = TRIM(UPPER(ddiag.icd_code)) AND dprim.icd_version = ddiag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      -- ICD code based matches
      (dprim.icd_version = 9 AND dprim.icd_code LIKE '428%')
      OR (dprim.icd_version = 10 AND UPPER(dprim.icd_code) LIKE 'I50%')
      -- or fallback on diagnosis text containing 'heart failure' (case-insensitive)
      OR (ddiag.long_title IS NOT NULL AND LOWER(ddiag.long_title) LIKE '%heart failure%')
    )
),

-- 2) Per-admission flags for CKD and Diabetes (any diagnosis row on that admission)
adm_diag_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '585%')
                  OR (icd_version = 10 AND UPPER(icd_code) LIKE 'N18%') THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '250%')
                  OR (icd_version = 10 AND (UPPER(icd_code) LIKE 'E10%' OR UPPER(icd_code) LIKE 'E11%' OR UPPER(icd_code) LIKE 'E13%')) THEN 1 ELSE 0 END) AS dm_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

-- 3) Combine cohort with diagnosis flags and day-1 ICU flag
cohort_with_flags AS (
  SELECT
    c.*,
    COALESCE(df.ckd_flag, 0) AS ckd_flag,
    COALESCE(df.dm_flag, 0) AS dm_flag,
    -- day1 ICU: EXISTS an icustay for same hadm_id with intime < admittime + 1 day
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = c.hadm_id
        AND icu.intime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
    ) AS icu_day1
  FROM
    cohort c
  LEFT JOIN
    adm_diag_flags df
  ON c.hadm_id = df.hadm_id
)

-- 4) Final aggregation: stratify by LOS group and day-1 ICU status
SELECT
  los_group,
  CASE WHEN icu_day1 THEN 'ICU day1' ELSE 'No ICU day1' END AS day1_icu_status,
  COUNT(*) AS admissions,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 2) AS ckd_prevalence_pct,
  ROUND(100.0 * SUM(dm_flag) / COUNT(*), 2) AS diabetes_prevalence_pct
FROM (
  SELECT
    *,
    CASE WHEN los_days <= 7 THEN '<=7' ELSE '>7' END AS los_group
  FROM
    cohort_with_flags
)
GROUP BY
  los_group,
  day1_icu_status,
  icu_day1
ORDER BY
  los_group DESC,
  day1_icu_status;