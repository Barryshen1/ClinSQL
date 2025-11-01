WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
)
, per_patient_counts AS (
  SELECT
    c.subject_id,
    -- count procedure rows whose description looks like "diagnostic cardiac catheterization"
    SUM(
      CASE
        WHEN d.long_title IS NOT NULL
         AND REGEXP_CONTAINS(LOWER(d.long_title), r'diagnostic')
         AND REGEXP_CONTAINS(LOWER(d.long_title), r'catheter')
         AND REGEXP_CONTAINS(LOWER(d.long_title), r'(card|heart|coronar)')
        THEN 1
        ELSE 0
      END
    ) AS num_diag_cath
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON c.subject_id = pr.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
   AND pr.icd_version = d.icd_version
  GROUP BY c.subject_id
)
SELECT
  MIN(num_diag_cath) AS min_diagnostic_cardacatheterizations_per_patient
FROM per_patient_counts;