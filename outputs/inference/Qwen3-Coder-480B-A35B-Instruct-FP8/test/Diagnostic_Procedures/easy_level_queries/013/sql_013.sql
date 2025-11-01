WITH valve_procs AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pr
  ON
    p.subject_id = pr.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
  ON
    pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND LOWER(d.long_title) LIKE '%valve%'
    AND (LOWER(d.long_title) LIKE '%repair%' OR LOWER(d.long_title) LIKE '%replacement%')
),
admission_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS proc_count
  FROM
    valve_procs
  GROUP BY
    hadm_id
)
SELECT
  MIN(proc_count) AS min_distinct_valve_procedures_per_hospitalization
FROM
  admission_counts;