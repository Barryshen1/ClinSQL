WITH patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(*) AS procedure_count
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON pi.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND (
      LOWER(dip.long_title) LIKE '%catheter ablation%'
      OR LOWER(dip.long_title) LIKE '%cardioversion%'
    )
  GROUP BY
    p.subject_id
)
SELECT
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(3)] - APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS iqr
FROM
  patient_procedure_counts;