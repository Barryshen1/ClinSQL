WITH
-- cohort of patients: female, age 76-86
cohort_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 76 AND 86
),

-- all admissions for cohort patients, compute next admission time per subject
admissions_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- next admission time for same subject
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort_patients cp
    ON a.subject_id = cp.subject_id
),

-- mark which admissions have any pneumonia diagnosis (look at diagnosis text)
admissions_with_pneumonia_flag AS (
  SELECT
    ac.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = ac.hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    ) THEN 1 ELSE 0 END AS is_pneumonia
  FROM admissions_cohort ac
),

-- medication counts: unique drugs in first 7 hospital days (starttime between admittime and admittime+7 days)
med_counts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT TRIM(LOWER(p.drug))) AS med_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN admissions_with_pneumonia_flag a
    ON p.hadm_id = a.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.starttime >= a.admittime
    AND p.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 7 DAY)
  GROUP BY a.hadm_id
),

-- assemble final set: only pneumonia admissions, attach med_count (0 if none), compute LOS and readmit flag
pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE(m.med_count, 0) AS med_count,
    -- LOS in days as fractional days
    CASE
      WHEN a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
      THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0
      ELSE NULL
    END AS los_days,
    -- next admission within 30 days after discharge
    CASE
      WHEN a.next_admittime IS NOT NULL
       AND a.dischtime IS NOT NULL
       AND a.next_admittime > a.dischtime
       AND TIMESTAMP_DIFF(a.next_admittime, a.dischtime, DAY) <= 30
      THEN 1 ELSE 0 END AS readmit_30d
  FROM admissions_with_pneumonia_flag a
  LEFT JOIN med_counts m
    ON a.hadm_id = m.hadm_id
  WHERE a.is_pneumonia = 1
    -- exclude admissions without discharge time (to allow LOS and readmit calculation)
    AND a.dischtime IS NOT NULL
)

-- final aggregation by tertile
SELECT
  tertile,
  COUNT(*) AS admissions_count,
  MIN(med_count) AS min_med_score,
  ROUND(AVG(med_count), 2) AS avg_med_score,
  MAX(med_count) AS max_med_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * AVG(CAST(readmit_30d AS FLOAT64)), 2) AS readmit_30d_pct
FROM (
  SELECT
    pa.*,
    NTILE(3) OVER (ORDER BY med_count, hadm_id) AS tertile
  FROM pneumonia_admissions pa
)
GROUP BY tertile
ORDER BY tertile;