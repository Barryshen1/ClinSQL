WITH first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN (
    SELECT subject_id, MIN(intime) AS first_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id
  ) first ON i.subject_id = first.subject_id AND i.intime = first.first_intime
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),

icu_patients AS (
  SELECT
    f.*,
    p.gender,
    p.anchor_age
  FROM first_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON f.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 60 AND 70
),

ich_patients AS (
  SELECT DISTINCT
    i.*
  FROM icu_patients i
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '852%')
    OR
    (d.icd_version = 10 AND d.icd_code LIKE 'S06.%')
    OR
    LOWER(dd.long_title) LIKE '%intracranial hem%'
),

procedures_first_72h AS (
  SELECT
    p.stay_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN ich_patients i ON p.stay_id = i.stay_id
  WHERE p.starttime >= i.intime AND p.starttime <= DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY p.stay_id
),

cohort_metrics AS (
  SELECT
    APPROX_QUANTILES(COALESCE(p.procedure_count, 0), 100)[OFFSET(75)] AS proc_burden_75th,
    AVG(i.los) AS mean_icu_los,
    AVG(CAST(i.hospital_expire_flag AS FLOAT64)) AS hospital_mortality
  FROM ich_patients i
  LEFT JOIN procedures_first_72h p ON i.stay_id = p.stay_id
),

general_icu_population AS (
  SELECT
    AVG(los) AS mean_icu_los_general,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_general
  FROM first_icu_stays
)

SELECT
  c.proc_burden_75th,
  c.mean_icu_los,
  c.hospital_mortality,
  g.mean_icu_los_general,
  g.hospital_mortality_general
FROM cohort_metrics c
CROSS JOIN general_icu_population g;