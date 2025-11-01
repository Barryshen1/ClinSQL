WITH ecg_telem_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE LOWER(long_description) LIKE '%ecg%'
     OR LOWER(long_description) LIKE '%ekg%'
     OR LOWER(long_description) LIKE '%electrocardiogram%'
     OR LOWER(long_description) LIKE '%telemetry%'
     OR LOWER(long_description) LIKE '%cardiac monitor%'
     OR LOWER(short_description) LIKE '%ecg%'
     OR LOWER(short_description) LIKE '%ekg%'
     OR LOWER(short_description) LIKE '%electrocardiogram%'
     OR LOWER(short_description) LIKE '%telemetry%'
     OR LOWER(short_description) LIKE '%cardiac monitor%'
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 51 AND 61
),
patient_procedure_counts AS (
  SELECT 
    c.subject_id,
    COUNT(h.hcpcs_cd) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON c.hadm_id = h.hadm_id
    AND h.hcpcs_cd IN (SELECT code FROM ecg_telem_codes)
  GROUP BY c.subject_id
)
SELECT 
  PERCENTILE_CONT(procedure_count, 0.25) OVER() AS percentile_25
FROM patient_procedure_counts
LIMIT 1;