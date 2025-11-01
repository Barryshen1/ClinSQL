WITH PatientAgeGroup AS (
  SELECT
    subject_id,
    CASE
      WHEN anchor_age BETWEEN 51 AND 61 THEN '51-61'
      ELSE 'Other'
    END AS age_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON pr.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
  WHERE
    pr.icd_code LIKE '93%' -- ECG/Telemetry procedures start with 93 in ICD-10
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, distinct_procedure_count) AS percentile_25
FROM
  ProcedureCounts;