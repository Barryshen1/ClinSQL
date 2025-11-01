WITH procedure_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%cardioversion%'
     OR LOWER(long_title) LIKE '%catheter ablation%'
),
patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(proc.icd_code) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  INNER JOIN procedure_codes pc
    ON proc.icd_code = pc.icd_code
    AND proc.icd_version = pc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
  GROUP BY p.subject_id
)
SELECT
  STDDEV(procedure_count) AS sd_procedures_per_patient
FROM patient_procedure_counts;