WITH patients_age_gender AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age BETWEEN 40 AND 50
),
-- Identify ARDS diagnoses (ICD-10: J80, ICD-9: 518.82)
ards_codes AS (
  SELECT 'J80' AS icd_code, 10 AS icd_version
  UNION ALL
  SELECT '518.82', 9
),
ards_hadm AS (
  SELECT DISTINCT
    pa.hadm_id
  FROM
    patients_age_gender pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pa.hadm_id = di.hadm_id
  INNER JOIN
    ards_codes ac
  ON
    di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
),
-- Lab events in first 72 hours, abnormal values
lab_abnormal AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN
    patients_age_gender pa
  ON
    le.hadm_id = pa.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_labitems dlab
  ON
    le.itemid = dlab.itemid
  WHERE
    le.charttime >= pa.admittime
    AND le.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (le.ref_range_lower IS NOT NULL OR le.ref_range_upper IS NOT NULL)
    AND (
      (le.valuenum < le.ref_range_lower AND le.ref_range_lower IS NOT NULL)
      OR (le.valuenum > le.ref_range_upper AND le.ref_range_upper IS NOT NULL)
    )
  GROUP BY
    le.hadm_id
),
-- Combine with ARDS status and abnormal count
cohort_with_abnormal AS (
  SELECT
    pa.hadm_id,
    pa.age_at_admit,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    pa.deathtime,
    CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards,
    COALESCE(lab.abnormal_lab_count, 0) AS abnormal_lab_count
  FROM
    patients_age_gender pa
  LEFT JOIN
    ards_hadm ards
  ON
    pa.hadm_id = ards.hadm_id
  LEFT JOIN
    lab_abnormal lab
  ON
    pa.hadm_id = lab.hadm_id
),
-- Compute 75th percentile of abnormal lab count among ARDS patients
ards_stats AS (
  SELECT
    APPROX_QUANTILES(abnormal_lab_count, 1000)[OFFSET(750)] AS p75_abnormal_count
  FROM
    cohort_with_abnormal
  WHERE
    has_ards = 1
),
-- High instability ARDS group: has_ards = 1 AND abnormal_lab_count >= p75
p75_val AS (
  SELECT p75_abnormal_count FROM ards_stats
),
high_instability_ards AS (
  SELECT
    'ARDS High Instability' AS cohort,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / 3600.0 / 24.0) AS mean_los_days,
    AVG(abnormal_lab_count) AS avg_critical_labs_per_patient
  FROM
    cohort_with_abnormal,
    p75_val
  WHERE
    has_ards = 1
    AND abnormal_lab_count >= p75_abnormal_count
),
-- Non-ARDS group: same age/gender, no ARDS, compute same metrics
non_ards AS (
  SELECT
    'Non-ARDS' AS cohort,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / 3600.0 / 24.0) AS mean_los_days,
    AVG(abnormal_lab_count) AS avg_critical_labs_per_patient
  FROM
    cohort_with_abnormal
  WHERE
    has_ards = 0
)
-- Combine results
SELECT
  cohort,
  ROUND(mortality_rate, 4) AS mortality_rate,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(avg_critical_labs_per_patient, 2) AS avg_critical_labs_per_patient
FROM
  high_instability_ards
UNION ALL
SELECT
  cohort,
  ROUND(mortality_rate, 4) AS mortality_rate,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(avg_critical_labs_per_patient, 2) AS avg_critical_labs_per_patient
FROM
  non_ards;