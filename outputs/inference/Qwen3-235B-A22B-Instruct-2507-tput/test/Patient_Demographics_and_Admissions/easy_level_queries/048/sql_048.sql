WITH heart_failure_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
),
filtered_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN heart_failure_patients hf ON p.subject_id = hf.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
),
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN filtered_patients fp ON a.subject_id = fp.subject_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND a.admittime = (
      SELECT MIN(a2.admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
    )
)
SELECT
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS iqr_los_days
FROM first_admissions;