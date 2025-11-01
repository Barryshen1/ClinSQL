WITH cohort AS (
  -- Select female patients aged 64-74
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),
cardiac_cath_procs AS (
  -- Identify diagnostic cardiac catheterization procedures
  SELECT
    p.subject_id,
    COUNT(*) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%diagnostic%'
    AND LOWER(d.long_title) LIKE '%cardiac catheterization%'
  GROUP BY
    p.subject_id
)
-- Compute the minimum per-patient count among our cohort (only those with ≥1)
SELECT
  MIN(proc_count) AS min_cardiac_cath_per_patient
FROM
  cardiac_cath_procs c
JOIN
  cohort co
  ON c.subject_id = co.subject_id;