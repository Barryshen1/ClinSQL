WITH icu_stays_base AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.gender,
    (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS age_at_admission,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
),
ards_cohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '51882')
     OR (icd_version = 10 AND icd_code = 'J80')
),
procedure_counts AS (
  SELECT 
    pe.stay_id,
    COUNT(DISTINCT pe.itemid) AS diagnostic_intensity
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pe.stay_id = icu.stay_id
  WHERE pe.starttime >= icu.intime
    AND pe.starttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY pe.stay_id
),
combined AS (
  SELECT 
    base.stay_id,
    base.hadm_id,
    base.gender,
    base.age_at_admission,
    base.hospital_expire_flag,
    base.hospital_los_days,
    CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards,
    COALESCE(proc.diagnostic_intensity, 0) AS diagnostic_intensity
  FROM icu_stays_base base
  LEFT JOIN ards_cohort ards
    ON base.hadm_id = ards.hadm_id
  LEFT JOIN procedure_counts proc
    ON base.stay_id = proc.stay_id
)
SELECT 
  'ARDS_cohort' AS cohort,
  APPROX_QUANTILES(diagnostic_intensity, 1000)[OFFSET(250)] AS p25_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 1000)[OFFSET(750)] AS p75_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 1000)[OFFSET(950)] AS p95_diagnostic_intensity,
  AVG(hospital_los_days) AS avg_hospital_los,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM combined
WHERE has_ards = 1 
  AND gender = 'F' 
  AND age_at_admission BETWEEN 84 AND 94

UNION ALL

SELECT 
  'General_ICU' AS cohort,
  APPROX_QUANTILES(diagnostic_intensity, 1000)[OFFSET(250)] AS p25_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 1000)[OFFSET(750)] AS p75_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 1000)[OFFSET(950)] AS p95_diagnostic_intensity,
  AVG(hospital_los_days) AS avg_hospital_los,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM combined;