WITH cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    (icd_version = 10 AND icd_code LIKE '0210%') OR
    (icd_version = 9 AND icd_code LIKE '361%')
),
patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_cabg_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN cabg_codes cc
    ON proc.icd_code = cc.icd_code AND proc.icd_version = cc.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
  GROUP BY p.subject_id
)
SELECT
  STDDEV(distinct_cabg_count) AS std_dev_distinct_cabg_per_patient
FROM patient_procedure_counts;