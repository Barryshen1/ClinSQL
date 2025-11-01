WITH PatientAsthma AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age >= 88
    AND p.anchor_age <= 98
    AND d.icd_code LIKE 'J45%' -- Asthma ICD-10 code
),
AdmissionProcedureCounts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientAsthma
    )
  GROUP BY
    a.hadm_id
),
AdmissionLength AS (
  SELECT
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS admission_length
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    hadm_id IN (
      SELECT
        hadm_id
      FROM AdmissionProcedureCounts
    )
)
SELECT
  CASE
    WHEN al.admission_length BETWEEN 1 AND 3
    THEN '1-3 days'
    WHEN al.admission_length BETWEEN 4 AND 7
    THEN '4-7 days'
    ELSE 'Other'
  END AS admission_length_group,
  APPROX_QUANTILES(apc.procedure_count, 3)[OFFSET(0)] AS percentile_25,
  APPROX_QUANTILES(apc.procedure_count, 3)[OFFSET(1)] AS percentile_50,
  APPROX_QUANTILES(apc.procedure_count, 3)[OFFSET(2)] AS percentile_75
FROM AdmissionProcedureCounts AS apc
JOIN AdmissionLength AS al
  ON apc.hadm_id = al.hadm_id
WHERE
  al.admission_length BETWEEN 1 AND 7
GROUP BY
  admission_length_group
ORDER BY
  admission_length_group;