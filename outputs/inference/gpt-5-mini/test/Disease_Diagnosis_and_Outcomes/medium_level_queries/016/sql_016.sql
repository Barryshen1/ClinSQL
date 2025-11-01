WITH ami_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    LOWER(dd.long_title) LIKE '%acute myocardial%' 
    OR LOWER(dd.long_title) LIKE '%myocardial infarction%' 
    OR LOWER(dd.long_title) LIKE '%myocardial infarct%'
  )
),
exclude_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    LOWER(dd.long_title) LIKE '%shock%'
    OR LOWER(dd.long_title) LIKE '%respiratory failure%'
    OR LOWER(dd.long_title) LIKE '%respiratory insufficiency%'
  )
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE a.hadm_id IN (SELECT hadm_id FROM ami_hadm)
    AND a.hadm_id NOT IN (SELECT hadm_id FROM exclude_hadm)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.dischtime IS NOT NULL
)

SELECT
  CASE WHEN los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group,
  CASE 
    WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = c.hadm_id
        -- ICU stay overlaps the first 24 hours of admission
        AND icu.intime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
        AND icu.outtime > c.admittime
    ) THEN 'ICU day 1'
    ELSE 'No ICU day 1'
  END AS icu_day1,
  COUNT(*) AS n_admissions,
  SAFE_DIVIDE(100.0 * SUM(CAST(c.hospital_expire_flag AS INT64)), COUNT(*)) AS in_hosp_mort_pct,
  APPROX_QUANTILES(c.los_days, 2)[OFFSET(1)] AS median_los_days
FROM cohort c
GROUP BY los_group, icu_day1
ORDER BY icu_day1 DESC, los_group;