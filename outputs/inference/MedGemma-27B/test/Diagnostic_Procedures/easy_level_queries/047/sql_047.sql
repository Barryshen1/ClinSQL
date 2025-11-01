WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 42 -- Specific patient ID
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON proc.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON proc.subject_id = p.subject_id
  WHERE
    proc.icd_code IN ('Z01.81', 'Z01.89', 'Z01.82') -- ICD-10 codes for cardioversion and ablation
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
  GROUP BY
    p.subject_id
)
SELECT
  STDDEV(distinct_procedure_count) AS sd_distinct_procedures
FROM
  ProcedureCounts;