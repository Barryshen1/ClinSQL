WITH patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
    ON p.subject_id = proc.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d_proc
    ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(d_proc.long_title) LIKE '%pacemaker%'
    OR LOWER(d_proc.long_title) LIKE '%defibrillator%'
    OR LOWER(d_proc.long_title) LIKE '%icd%'
  GROUP BY
    p.subject_id
)

SELECT
  APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(25)] AS percentile_25
FROM
  patient_procedure_counts;