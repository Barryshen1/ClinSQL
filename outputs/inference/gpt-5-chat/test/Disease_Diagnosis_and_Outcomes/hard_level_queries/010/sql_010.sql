WITH male_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),
drg_severity_per_hadm AS (
  SELECT
    hadm_id,
    MAX(CAST(drg_severity AS INT64)) AS drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  GROUP BY hadm_id
),
diagnosis_flags AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN LOWER(diag.long_title) LIKE '%ketoacidosis%' THEN 1 ELSE 0 END) AS dka_flag,
    MAX(CASE WHEN LOWER(diag.long_title) LIKE '%cardi%' THEN 1 ELSE 0 END) AS cardio_flag,
    MAX(CASE WHEN LOWER(diag.long_title) LIKE '%neuro%' THEN 1 ELSE 0 END) AS neuro_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code
    AND d.icd_version = diag.icd_version
  GROUP BY d.subject_id, d.hadm_id
),
cohort_with_flags AS (
  SELECT
    mc.*,
    df.dka_flag,
    df.cardio_flag,
    df.neuro_flag,
    drg.drg_severity,
    DATE_DIFF(COALESCE(mc.dod, mc.deathtime), mc.admittime, DAY) AS days_to_death
  FROM male_cohort mc
  LEFT JOIN diagnosis_flags df
    ON mc.subject_id = df.subject_id AND mc.hadm_id = df.hadm_id
  LEFT JOIN drg_severity_per_hadm drg
    ON mc.hadm_id = drg.hadm_id
),
percentile_calc AS (
  SELECT
    subject_id,
    hadm_id,
    drg_severity,
    PERCENT_RANK() OVER (ORDER BY drg_severity) AS severity_percentile
  FROM cohort_with_flags
  WHERE drg_severity IS NOT NULL
)
SELECT
  CASE WHEN cwf.dka_flag = 1 THEN 'DKA' ELSE 'All_Males' END AS group_name,
  COUNT(*) AS n,
  AVG(cwf.drg_severity) AS mean_risk_score,
  AVG(CASE WHEN cwf.days_to_death IS NOT NULL AND cwf.days_to_death <= 30 THEN 1 ELSE 0 END) AS mortality_30d,
  AVG(cwf.cardio_flag) AS cardiovascular_complication_rate,
  AVG(cwf.neuro_flag) AS neurologic_complication_rate,
  AVG(CASE WHEN cwf.hospital_expire_flag = 0 THEN DATE_DIFF(cwf.dischtime, cwf.admittime, DAY) END) AS mean_survivor_los_days,
  AVG(pc.severity_percentile) AS mean_risk_percentile
FROM cohort_with_flags cwf
LEFT JOIN percentile_calc pc
  ON cwf.subject_id = pc.subject_id AND cwf.hadm_id = pc.hadm_id
GROUP BY group_name
ORDER BY group_name;