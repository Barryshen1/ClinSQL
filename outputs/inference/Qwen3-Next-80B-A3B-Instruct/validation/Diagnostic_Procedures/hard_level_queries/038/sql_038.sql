WITH first_icu_stays AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.anchor_age BETWEEN 60 AND 70
    AND p.gender = 'M'
),

ich_cohort AS (
  SELECT f.*
  FROM first_icu_stays f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code IN ('430','431','432'))
     OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
  AND f.rn = 1
),

cohort_procedures AS (
  SELECT 
    i.subject_id,
    COUNT(pe.itemid) AS procedure_count
  FROM ich_cohort i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL '72 hours'
  GROUP BY i.subject_id
),

cohort_metrics AS (
  SELECT
    PERCENTILE_CONT(cp.procedure_count, 0.75) AS p75_procedure_burden,
    AVG(i.los) AS mean_icu_los_cohort,
    AVG(CAST(i.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_cohort
  FROM ich_cohort i
  LEFT JOIN cohort_procedures cp
    ON i.subject_id = cp.subject_id
),

general_icu AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
),

general_metrics AS (
  SELECT
    AVG(los) AS mean_icu_los_general,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_general
  FROM general_icu
  WHERE rn = 1
)

SELECT
  cm.p75_procedure_burden,
  cm.mean_icu_los_cohort,
  cm.hospital_mortality_cohort,
  gm.mean_icu_los_general,
  gm.hospital_mortality_general
FROM cohort_metrics cm
CROSS JOIN general_metrics gm;