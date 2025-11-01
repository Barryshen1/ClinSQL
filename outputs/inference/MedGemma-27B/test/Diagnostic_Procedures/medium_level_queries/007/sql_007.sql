WITH PatientACS AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_code IN ('410', '411', '413', '414', '427', '428') -- ACS ICD-10 codes
),
AdmissionACS AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientACS AS pa
    ON a.subject_id = pa.subject_id
),
ProcedureCounts AS (
  SELECT
    a.hadm_id,
    COUNT(p.seq_num) AS procedure_count
  FROM AdmissionACS AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.hadm_id = p.hadm_id
  GROUP BY
    a.hadm_id
),
DiagnosisType AS (
  SELECT
    hadm_id,
    icd_code,
    seq_num,
    CASE
      WHEN seq_num = 1
      THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
)
SELECT
  CASE
    WHEN a.los BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN a.los BETWEEN 5 AND 8
    THEN '5-8 days'
    ELSE 'Other'
  END AS los_group,
  dt.diagnosis_type,
  PERCENTILE_CONT(pc.procedure_count, 0.25) AS p25,
  PERCENTILE_CONT(pc.procedure_count, 0.50) AS p50,
  PERCENTILE_CONT(pc.procedure_count, 0.75) AS p75
FROM AdmissionACS AS a
JOIN ProcedureCounts AS pc
  ON a.hadm_id = pc.hadm_id
JOIN DiagnosisType AS dt
  ON a.hadm_id = dt.hadm_id
WHERE
  dt.icd_code IN ('410', '411', '413', '414', '427', '428') -- ACS ICD-10 codes
GROUP BY
  los_group,
  dt.diagnosis_type
ORDER BY
  los_group,
  dt.diagnosis_type;