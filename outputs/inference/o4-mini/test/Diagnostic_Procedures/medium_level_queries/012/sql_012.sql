WITH acs_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
  WHERE
    -- Male, age between 35 and 45
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    -- Primary diagnosis is ACS (ICD-10 contains myocardial infarction or unstable angina)
    AND d.seq_num = 1
    AND (
      LOWER(di.long_title) LIKE '%myocardial%'
      OR LOWER(di.long_title) LIKE '%angina%'
    )
    -- Keep only los 1-7 days
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

ultrasound_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS us_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    LOWER(short_description) LIKE '%ultrasound%'
    OR LOWER(short_description) LIKE '%echocardi%'
  GROUP BY
    hadm_id
)

SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_bucket,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(AVG(COALESCE(us.us_count, 0)), 2) AS mean_ultrasounds_per_admission
FROM
  acs_adm a
  LEFT JOIN ultrasound_counts us
    ON a.hadm_id = us.hadm_id
GROUP BY
  los_bucket
ORDER BY
  los_bucket;