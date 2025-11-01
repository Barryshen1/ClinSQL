WITH eligible_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    TIMESTAMP_DIFF(
      a.admittime, 
      DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
      INTERVAL p.anchor_age YEAR), 
      YEAR
    ) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND TIMESTAMP_DIFF(
        a.admittime, 
        DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
        INTERVAL p.anchor_age YEAR), 
        YEAR
      ) BETWEEN 84 AND 94
),
echocardiography_procedures AS (
  SELECT 
    e.subject_id,
    p.icd_code
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
    ON e.subject_id = p.subject_id AND e.hadm_id = p.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%echocardiography%'
),
distinct_procedures_per_patient AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM echocardiography_procedures
  GROUP BY subject_id
)
SELECT MAX(distinct_procedure_count) AS max_distinct_procedures
FROM distinct_procedures_per_patient;