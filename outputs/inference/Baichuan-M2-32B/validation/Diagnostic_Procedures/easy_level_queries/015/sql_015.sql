WITH cabg_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE icd_version = 9
    AND icd_code LIKE '36.1%'
),
patient_procedures AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    pr.chartdate,
    pr.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE pr.icd_code IN (SELECT icd_code FROM cabg_codes)
    AND p.gender = 'M'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND pr.chartdate IS NOT NULL
),
patient_age_at_procedure AS (
  SELECT 
    subject_id,
    icd_code,
    chartdate,
    EXTRACT(YEAR FROM chartdate) - (anchor_year - anchor_age) AS age_at_procedure
  FROM patient_procedures
),
filtered_patients AS (
  SELECT 
    subject_id,
    icd_code
  FROM patient_age_at_procedure
  WHERE age_at_procedure BETWEEN 45 AND 55
),
distinct_cabg_per_patient AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_cabg_count
  FROM filtered_patients
  GROUP BY subject_id
)
SELECT 
  APPROX_QUANTILES(distinct_cabg_count, 4)[OFFSET(1)] AS p25
FROM distinct_cabg_per_patient;