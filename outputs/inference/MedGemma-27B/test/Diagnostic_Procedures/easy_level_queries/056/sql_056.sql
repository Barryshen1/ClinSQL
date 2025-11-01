WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 43 AND 53
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    ) AND d.long_title LIKE '%mechanical circulatory support%'
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(distinct_procedure_count, 0.25) AS percentile_25
FROM ProcedureCounts;