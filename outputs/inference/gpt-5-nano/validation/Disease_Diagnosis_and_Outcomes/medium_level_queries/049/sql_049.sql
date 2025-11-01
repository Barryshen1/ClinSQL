WITH
  -- Per-admission STEMI vs NSTEMI flags (ICD-10 codes)
  stemi_nstemi AS (
    SELECT
      hadm_id,
      MAX(CASE WHEN icd_code IN ('I21.0','I21.1','I21.2','I21.3') THEN 1 ELSE 0 END) AS has_stemi,
      MAX(CASE WHEN icd_code IN ('I21.4','I21.5','I21.6','I21.7','I21.8','I21.9') THEN 1 ELSE 0 END) AS has_nstemi
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
  ),

  -- CKD presence per admission (approx.)
  ckd_presence AS (
    SELECT
      hadm_id,
      CASE WHEN SUM(CASE WHEN icd_code LIKE 'N18%' OR icd_code LIKE '585%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS ckd_present
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
  ),

  -- Diabetes presence per admission (approx.)
  diabetes_presence AS (
    SELECT
      hadm_id,
      CASE WHEN SUM(CASE WHEN icd_code LIKE 'E1%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS diabetes_present
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
  ),

  -- Base cohort: filter to male 51–61, include only MI admissions, compute LOS
  base AS (
    SELECT
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      p.gender,
      p.anchor_age,
      CASE
        WHEN s.has_stemi = 1 THEN 'STEMI'
        WHEN s.has_nstemi = 1 THEN 'NSTEMI'
      END AS mi_type,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
      -- comorbidity flags (0/1)
      COALESCE(c.ckd_present, 0) AS ckd_present,
      COALESCE(d.diabetes_present, 0) AS diabetes_present
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN stemi_nstemi s
      ON a.hadm_id = s.hadm_id
    LEFT JOIN ckd_presence c
      ON a.hadm_id = c.hadm_id
    LEFT JOIN diabetes_presence d
      ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 51 AND 61
      AND (s.has_stemi = 1 OR s.has_nstemi = 1)
      -- require discharge (so in-hospital mortality is defined) and LOS >= 1 day
      AND a.dischtime IS NOT NULL
      AND a.admittime IS NOT NULL
      AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 1
  )

SELECT
  mi_type,
  CASE
    WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
    WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
    WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
    WHEN los_days >= 10 THEN '>=10'
  END AS los_bucket,
  CASE
    -- comorb_group: 0-1 if 0 or 1 comorbidity, 2 if both CKD and Diabetes present
    -- Note: with this simple mapping, maximum is 2
    WHEN (ckd_present + diabetes_present) >= 2 THEN '2'
    WHEN (ckd_present + diabetes_present) = 1 THEN '0-1'
    ELSE '0-1'
  END AS comorb_group,
  COUNT(*) AS N,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS Deaths,
  SAFE_DIVIDE(
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END),
    COUNT(*)
  ) * 100 AS inhospital_mortality_pct,
  AVG(CASE WHEN ckd_present = 1 THEN 1.0 ELSE 0.0 END) * 100 AS ckd_prevalence_pct,
  AVG(CASE WHEN diabetes_present = 1 THEN 1.0 ELSE 0.0 END) * 100 AS diabetes_prevalence_pct
FROM base
GROUP BY mi_type, los_bucket, comorb_group
ORDER BY mi_type, los_bucket, comorb_group;