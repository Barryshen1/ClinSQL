WITH patients_with_age AS (
  SELECT
    subject_id,
    gender,
    anchor_year,
    anchor_age,
    dod,
    DATE_SUB(CAST(CONCAT(CAST(anchor_year AS STRING), '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
admissions_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_with_age p ON a.subject_id = p.subject_id
),
septic_shock_diagnoses AS (
  SELECT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code IN ('R65.20', 'R65.21', 'R65.22', 'R65.28', 'R65.29'))
    OR (icd_version = 9 AND icd_code = '785.52')
),
cohort_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.age_at_admission,
    COUNT(DISTINCT d.icd_code) AS num_diagnoses,
    MAX(CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS has_septic_shock
  FROM admissions_with_age a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  LEFT JOIN septic_shock_diagnoses s ON a.hadm_id = s.hadm_id
  WHERE
    a.gender = 'M'
    AND a.age_at_admission BETWEEN 63 AND 73
  GROUP BY
    a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.age_at_admission
  HAVING
    num_diagnoses > 15
    AND has_septic_shock = 1
),
cohort_metrics AS (
  SELECT
    hadm_id,
    died_within_90_days,
    los_survivor,
    num_diagnoses,
    age_at_admission
  FROM (
    SELECT
      c.hadm_id,
      c.subject_id,
      c.num_diagnoses,
      c.age_at_admission,
      -- 90-day mortality: 1 if died within 90 days, else 0
      IF(p.dod <= DATE(c.admittime) + 90, 1, 0) AS died_within_90_days,
      -- Survivor LOS: only for patients who survived admission
      CASE WHEN c.hospital_expire_flag = 0 THEN c.los END AS los_survivor
    FROM cohort_admissions c
    JOIN patients_with_age p ON c.subject_id = p.subject_id
  )
),
cohort_summary AS (
  SELECT
    AVG(num_diagnoses) AS mean_risk_score,  -- Using diagnoses count as risk proxy
    AVG(died_within_90_days) AS mean_90day_mortality,
    NULL AS major_complication_rate,  -- Ambiguous definition; left as NULL
    AVG(los_survivor) AS mean_survivor_los
  FROM cohort_metrics
),
general_population_metrics AS (
  SELECT
    AVG(died_within_90_days) AS general_mean_90day_mortality,
    AVG(los_survivor) AS general_mean_survivor_los
  FROM (
    SELECT
      a.hadm_id,
      a.subject_id,
      a.age_at_admission,
      -- 90-day mortality
      IF(p.dod <= DATE(a.admittime) + 90, 1, 0) AS died_within_90_days,
      -- Survivor LOS
      CASE WHEN a.hospital_expire_flag = 0 THEN a.los END AS los_survivor
    FROM admissions_with_age a
    JOIN patients_with_age p ON a.subject_id = p.subject_id
    WHERE
      a.gender = 'M'
      AND a.age_at_admission BETWEEN 63 AND 73
      AND (a.hadm_id NOT IN (SELECT hadm_id FROM cohort_admissions) OR num_diagnoses <= 15)
  )
),
cohort_with_percentile AS (
  SELECT
    hadm_id,
    died_within_90_days,
    los_survivor,
    num_diagnoses,
    age_at_admission,
    PERCENT_RANK() OVER (ORDER BY num_diagnoses) AS percentile
  FROM cohort_metrics
),
profile_percentile AS (
  SELECT
    percentile
  FROM cohort_with_percentile
  WHERE
    age_at_admission = 68
    AND num_diagnoses = 16
  LIMIT 1
)
SELECT
  cs.mean_risk_score,
  cs.mean_90day_mortality,
  cs.major_complication_rate,
  cs.mean_survivor_los,
  gp.general_mean_90day_mortality,
  gp.general_mean_survivor_los,
  pp.percentile AS profile_percentile
FROM cohort_summary cs
CROSS JOIN general_population_metrics gp
LEFT JOIN profile_percentile pp ON TRUE;