WITH cardiac_procs_per_admission AS (
  SELECT
    p.subject_id,
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_cardiac_procs
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON proc.icd_code = d_proc.icd_code
    AND proc.icd_version = d_proc.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND d_proc.icd_code LIKE '1%'  -- Cardiac procedures in ICD-9
  GROUP BY
    p.subject_id, proc.hadm_id
)

SELECT
  APPROX_QUANTILES(distinct_cardiac_procs, 100)[OFFSET(25)] AS percentile_25_distinct_cardiac_procs
FROM
  cardiac_procs_per_admission;