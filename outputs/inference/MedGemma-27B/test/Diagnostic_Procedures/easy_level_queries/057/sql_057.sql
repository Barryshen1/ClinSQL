WITH relevant_procedures AS (
  SELECT
    p.subject_id,
    COUNT(p.icd_code) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
    ON p.icd_code = dip.icd_code AND p.icd_version = dip.icd_version
  WHERE
    dip.long_title LIKE '%cardiac catheterization%'
  GROUP BY
    p.subject_id
),
patient_demographics AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
)
SELECT
  MIN(rp.procedure_count) AS min_procedure_count
FROM
  relevant_procedures AS rp
JOIN
  patient_demographics AS pd
  ON rp.subject_id = pd.subject_id
WHERE
  pd.gender = 'F' AND pd.anchor_age BETWEEN 64 AND 74;