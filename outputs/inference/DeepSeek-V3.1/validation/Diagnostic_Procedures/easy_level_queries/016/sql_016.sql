WITH ecg_procedures AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'(ecg|electrocardiogram|telemetry|monitoring)')
),
patient_admissions AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),
procedure_counts AS (
  SELECT 
    pa.hadm_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '_', proc.icd_version)) AS distinct_ecg_count
  FROM patient_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON pa.hadm_id = proc.hadm_id
  LEFT JOIN ecg_procedures ep
    ON proc.icd_code = ep.icd_code AND proc.icd_version = ep.icd_version
  GROUP BY pa.hadm_id
)
SELECT 
  APPROX_QUANTILES(distinct_ecg_count, 100)[OFFSET(75)] AS percentile_75
FROM procedure_counts;