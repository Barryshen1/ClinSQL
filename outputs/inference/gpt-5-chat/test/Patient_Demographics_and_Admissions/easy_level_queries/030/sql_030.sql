WITH cohort AS (
  -- Join patients, admissions, prescriptions
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.subject_id = pr.subject_id
    AND a.hadm_id = pr.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(pr.drug) LIKE '%heparin%'
      OR LOWER(pr.drug) LIKE '%warfarin%'
      OR LOWER(pr.drug) LIKE '%dabigatran%'
      OR LOWER(pr.drug) LIKE '%rivaroxaban%'
      OR LOWER(pr.drug) LIKE '%apixaban%'
      OR LOWER(pr.drug) LIKE '%edoxaban%'
      OR LOWER(pr.drug) LIKE '%enoxaparin%'
)
, first_admission AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime
  FROM (
    SELECT
      c.*,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM cohort c
  )
  WHERE rn = 1
    AND dischtime IS NOT NULL
)
SELECT
  STDDEV_SAMP(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS sd_los_days
FROM first_admission;