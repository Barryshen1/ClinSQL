WITH patients_male_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 77 AND 87
),
asthma_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
    AND (
      (icd_version = 9 AND icd_code LIKE '493%')
      OR (icd_version = 10 AND icd_code LIKE 'J45%')
    )
),
qualifying_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_male_age p ON a.subject_id = p.subject_id
  INNER JOIN asthma_admissions ast ON a.hadm_id = ast.hadm_id
),
first_icu_stays AS (
  SELECT qa.*, i.stay_id, i.intime,
         ROW_NUMBER() OVER (PARTITION BY qa.hadm_id ORDER BY i.intime ASC) AS stay_order
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON qa.hadm_id = i.hadm_id
  WHERE i.intime IS NOT NULL
),
first_stays_only AS (
  SELECT *
  FROM first_icu_stays
  WHERE stay_order = 1
),
cohort_with_procedures AS (
  SELECT 
    fso.*,
    TIMESTAMP_DIFF(fso.dischtime, fso.admittime, HOUR) / 24.0 AS hospital_los_days,
    (SELECT COUNT(*)
     FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
     WHERE pe.stay_id = fso.stay_id
       AND pe.starttime >= fso.intime
       AND pe.starttime < TIMESTAMP_ADD(fso.intime, INTERVAL 72 HOUR)
    ) AS procedure_count
  FROM first_stays_only fso
),
cohort_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM cohort_with_procedures
  WHERE procedure_count IS NOT NULL  -- Ensure valid counts
)
SELECT 
  quartile,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days,
  ROUND(AVG(hospital_expire_flag), 4) AS hospital_mortality
FROM cohort_quartiles
GROUP BY quartile
ORDER BY quartile;