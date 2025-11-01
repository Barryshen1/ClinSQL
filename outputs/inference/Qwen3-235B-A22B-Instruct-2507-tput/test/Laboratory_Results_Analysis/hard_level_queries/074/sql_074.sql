WITH patients_with_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
),
heart_failure_patients AS (
  SELECT DISTINCT
    pwa.*
  FROM patients_with_age pwa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pwa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I50%'
    AND di.icd_version = 10
),
target_cohort AS (
  SELECT DISTINCT
    hfp.subject_id,
    hfp.hadm_id,
    hfp.admittime,
    hfp.dischtime,
    hfp.hospital_expire_flag,
    hfp.deathtime
  FROM heart_failure_patients hfp
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON hfp.hadm_id = icu.hadm_id
  WHERE hfp.gender = 'M'
    AND hfp.age_at_admission BETWEEN 37 AND 47
    AND icu.intime <= hfp.admittime + INTERVAL '72' HOUR
),
general_inpatients AS (
  SELECT
    pwa.subject_id,
    pwa.hadm_id,
    pwa.admittime,
    pwa.dischtime,
    pwa.hospital_expire_flag,
    pwa.deathtime
  FROM patients_with_age pwa
),
target_lab_scores AS (
  SELECT
    tc.hadm_id,
    tc.admittime,
    tc.dischtime,
    tc.hospital_expire_flag,
    tc.deathtime,
    COUNT(DISTINCT le.itemid) AS unique_critical_labs
  FROM target_cohort tc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON tc.hadm_id = le.hadm_id
    AND le.charttime <= tc.admittime + INTERVAL '72' HOUR
    AND LOWER(le.flag) IN ('critically high', 'critically low')
  GROUP BY tc.hadm_id, tc.admittime, tc.dischtime, tc.hospital_expire_flag, tc.deathtime
),
general_lab_scores AS (
  SELECT
    gi.hadm_id,
    gi.admittime,
    gi.dischtime,
    gi.hospital_expire_flag,
    gi.deathtime,
    COUNT(DISTINCT le.itemid) AS unique_critical_labs
  FROM general_inpatients gi
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON gi.hadm_id = le.hadm_id
    AND le.charttime <= gi.admittime + INTERVAL '72' HOUR
    AND LOWER(le.flag) IN ('critically high', 'critically low')
  GROUP BY gi.hadm_id, gi.admittime, gi.dischtime, gi.hospital_expire_flag, gi.deathtime
),
target_stats AS (
  SELECT
    'Target Cohort' AS cohort,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(unique_critical_labs) AS avg_unique_critical_labs
  FROM target_lab_scores
),
general_stats AS (
  SELECT
    'General Inpatients' AS cohort,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(unique_critical_labs) AS avg_unique_critical_labs
  FROM general_lab_scores
)
SELECT
  cohort,
  ROUND(avg_los_days, 2) AS avg_los_days,
  ROUND(mortality_rate * 100, 2) AS mortality_rate_percent,
  ROUND(avg_unique_critical_labs, 2) AS avg_unique_critical_labs
FROM target_stats
UNION ALL
SELECT
  cohort,
  ROUND(avg_los_days, 2) AS avg_los_days,
  ROUND(mortality_rate * 100, 2) AS mortality_rate_percent,
  ROUND(avg_unique_critical_labs, 2) AS avg_unique_critical_labs
FROM general_stats
ORDER BY cohort;