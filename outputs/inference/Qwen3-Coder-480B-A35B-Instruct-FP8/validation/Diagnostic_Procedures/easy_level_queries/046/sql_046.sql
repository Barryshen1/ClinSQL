WITH mech_support_admissions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    COUNT(*) AS distinct_procedure_count
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd pr
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
    ON pr.icd_code = d.icd_code AND pr.icd_version = d.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pa
    ON pr.subject_id = pa.subject_id
  WHERE
    LOWER(d.long_title) LIKE '%mechanical%circulatory%'
    AND pa.gender = 'M'
    AND pa.anchor_age BETWEEN 80 AND 90
  GROUP BY
    pr.subject_id, pr.hadm_id
)
SELECT
  MAX(distinct_procedure_count) AS max_distinct_mech_support_per_hosp
FROM
  mech_support_admissions;