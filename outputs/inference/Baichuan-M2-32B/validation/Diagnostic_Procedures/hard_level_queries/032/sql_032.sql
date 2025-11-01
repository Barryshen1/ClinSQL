WITH first_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
sepsis_diagnoses AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.icd_version = 10
    AND (dd.icd_code LIKE 'A40%' OR dd.icd_code LIKE 'A41%' OR dd.icd_code LIKE 'R65%')
),
all_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    f.stay_id,
    f.intime,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN first_icu_stays f
    ON p.subject_id = f.subject_id AND a.hadm_id = f.hadm_id
  LEFT JOIN sepsis_diagnoses s
    ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    AND f.stay_seq = 1
),
procedures_48h AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.has_sepsis,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM all_patients ap
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ap.subject_id = pe.subject_id
    AND ap.stay_id = pe.stay_id
    AND pe.starttime BETWEEN ap.intime AND TIMESTAMP_ADD(ap.intime, INTERVAL 48 HOUR)
  WHERE ap.has_sepsis = 1
  GROUP BY ap.subject_id, ap.hadm_id, ap.has_sepsis  -- Fixed missing comma
),
sepsis_metrics AS (
  SELECT
    APPROX_QUANTILES(p.distinct_procedures, 100)[OFFSET(90)] AS p90_procedures,  -- Fixed column reference
    AVG(los_days) AS avg_los_sepsis,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_sepsis
  FROM all_patients
  LEFT JOIN procedures_48h p
    ON all_patients.subject_id = p.subject_id 
    AND all_patients.hadm_id = p.hadm_id
  WHERE has_sepsis = 1
),
control_metrics AS (
  SELECT
    AVG(los_days) AS avg_los_control,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_control
  FROM all_patients
  WHERE has_sepsis = 0
)
SELECT
  '90th_percentile_procedures' AS metric,
  'sepsis' AS group,
  p90_procedures AS value
FROM sepsis_metrics
UNION ALL
SELECT
  'avg_los',
  'sepsis',
  avg_los_sepsis
FROM sepsis_metrics
UNION ALL
SELECT
  'mortality_rate',
  'sepsis',
  mortality_sepsis
FROM sepsis_metrics
UNION ALL
SELECT
  'avg_los',
  'control',
  avg_los_control
FROM control_metrics
UNION ALL
SELECT
  'mortality_rate',
  'control',
  mortality_control
FROM control_metrics;