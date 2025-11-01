WITH sepsis_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON p.subject_id = d.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN physionet-data.mimiciv_3_1_icu.icustays i ON p.subject_id = i.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (LOWER(di.long_title) LIKE '%sepsis%' OR LOWER(di.long_title) LIKE '%septicemia%')
),
non_sepsis_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_icu.icustays i ON p.subject_id = i.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND p.subject_id NOT IN (SELECT subject_id FROM sepsis_cohort)
),
procedures_first_24h AS (
  SELECT
    c.subject_id,
    COUNT(pe.itemid) AS num_procedures
  FROM (
    SELECT subject_id, stay_id, intime FROM sepsis_cohort
    UNION ALL
    SELECT subject_id, stay_id, intime FROM non_sepsis_cohort
  ) c
  JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id
),
percentiles AS (
  SELECT
    PERCENTILE_CONT(num_procedures, 0.75) OVER () AS p75_procedures,
    PERCENTILE_CONT(num_procedures, 0.90) OVER () AS p90_procedures
  FROM procedures_first_24h
  LIMIT 1
),
cohort_summary AS (
  SELECT
    'Sepsis' AS cohort,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS avg_hospital_mortality
  FROM sepsis_cohort
  UNION ALL
  SELECT
    'Non-Sepsis' AS cohort,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS avg_hospital_mortality
  FROM non_sepsis_cohort
)
SELECT
  p.p75_procedures,
  p.p90_procedures,
  cs.cohort,
  cs.avg_icu_los,
  cs.avg_hospital_mortality
FROM percentiles p
CROSS JOIN cohort_summary cs
ORDER BY cs.cohort;