WITH mechanical_support_procs AS (
  SELECT
    p.subject_id,
    pr.icd_code,
    pr.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code AND pr.icd_version = dpr.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      LOWER(dpr.long_title) LIKE '%balloon pump%'
      OR LOWER(dpr.long_title) LIKE '%ventricular assist%'
      OR LOWER(dpr.long_title) LIKE '%ecmo%'
      OR LOWER(dpr.long_title) LIKE '%extracorporeal membrane%'
      OR LOWER(dpr.long_title) LIKE '%mechanical circulatory support%'
    )
)
, proc_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS num_distinct_mech_support_procs
  FROM
    mechanical_support_procs
  GROUP BY
    subject_id
)
SELECT
  MIN(num_distinct_mech_support_procs) AS min_distinct_mech_support_procs_per_patient
FROM
  proc_counts;