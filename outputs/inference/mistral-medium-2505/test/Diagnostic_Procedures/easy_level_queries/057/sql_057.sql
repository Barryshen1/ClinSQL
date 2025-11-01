WITH female_patients_64_74 AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),

cardiac_cath_procedures AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS procedure_count
  FROM
    female_patients_64_74 p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE
    -- ICD-9 codes for cardiac catheterization (diagnostic)
    (pr.icd_version = 9 AND pr.icd_code IN ('3721', '3722', '3723', '8855', '8856', '8857'))
    OR
    -- ICD-10 codes for cardiac catheterization (diagnostic)
    (pr.icd_version = 10 AND pr.icd_code LIKE 'I21%' OR pr.icd_code LIKE 'I22%' OR pr.icd_code LIKE 'I23%' OR pr.icd_code LIKE 'I24%' OR pr.icd_code LIKE 'I25%' OR pr.icd_code LIKE 'Z0181%')
  GROUP BY
    p.subject_id
)

SELECT
  MIN(procedure_count) AS min_procedures_per_patient
FROM
  cardiac_cath_procedures
WHERE
  procedure_count > 0;