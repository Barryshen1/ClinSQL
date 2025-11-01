WITH patient_ami_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    CASE WHEN di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' THEN 1 ELSE 0 END AS has_ami
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id AND di.icd_version = 10
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 42 AND 52
),
patient_procedures AS (
  SELECT
    pac.subject_id,
    pac.hadm_id,
    pac.stay_id,
    pac.los_days,
    pac.hospital_expire_flag,
    pac.has_ami,
    COUNT(DISTINCT pe.itemid) AS diag_intensity
  FROM patient_ami_cohort pac
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON pac.stay_id = pe.stay_id
    AND pe.starttime >= pac.intime
    AND pe.starttime <= DATETIME_ADD(pac.intime, INTERVAL 72 HOUR)
  GROUP BY pac.subject_id, pac.hadm_id, pac.stay_id, pac.los_days, pac.hospital_expire_flag, pac.has_ami
),
ami_stats AS (
  SELECT
    'AMI' AS group_label,
    APPROX_QUANTILES(CAST(diag_intensity AS FLOAT64), 100)[OFFSET(90)] AS p90_diagnostic_intensity,
    AVG(los_days) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM patient_procedures
  WHERE has_ami = 1
),
non_ami_stats AS (
  SELECT
    'non-AMI' AS group_label,
    CAST(NULL AS FLOAT64) AS p90_diagnostic_intensity,
    AVG(los_days) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM patient_procedures
  WHERE has_ami = 0
)
SELECT * FROM ami_stats
UNION ALL
SELECT * FROM non_ami_stats;