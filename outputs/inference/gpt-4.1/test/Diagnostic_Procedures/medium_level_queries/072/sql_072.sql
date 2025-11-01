WITH cohort AS (
  -- Select admissions for women age 52-62 with acute pancreatitis as primary diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    a.admission_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    -- Acute pancreatitis ICD codes
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND d.seq_num = 1 -- primary diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5770', '5771', '5772', '5779'))
      OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'K85')
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
diagnostic_procs AS (
  -- Identify diagnostic procedures for each admission
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.seq_num,
    pr.icd_code,
    pr.icd_version,
    dp.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    -- Heuristic: procedure long_title contains 'diagnostic'
    LOWER(dp.long_title) LIKE '%diagnostic%'
),
proc_counts AS (
  -- Count diagnostic procedures per admission, split by primary/secondary
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE
      WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN c.los_days BETWEEN 5 AND 8 THEN '5-8'
    END AS los_group,
    -- Count primary and secondary diagnostic procedures
    SUM(CASE WHEN dp.seq_num = 1 THEN 1 ELSE 0 END) AS primary_diag_proc_count,
    SUM(CASE WHEN dp.seq_num > 1 THEN 1 ELSE 0 END) AS secondary_diag_proc_count
  FROM
    cohort c
    LEFT JOIN diagnostic_procs dp
      ON c.subject_id = dp.subject_id AND c.hadm_id = dp.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, los_group
),
final AS (
  -- Unpivot for aggregation
  SELECT
    los_group,
    'primary' AS procedure_type,
    primary_diag_proc_count AS proc_count
  FROM proc_counts
  UNION ALL
  SELECT
    los_group,
    'secondary' AS procedure_type,
    secondary_diag_proc_count AS proc_count
  FROM proc_counts
)
SELECT
  los_group,
  procedure_type,
  ROUND(AVG(proc_count),2) AS mean_proc_per_adm,
  MIN(proc_count) AS min_proc_per_adm,
  MAX(proc_count) AS max_proc_per_adm
FROM
  final
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group, procedure_type
ORDER BY
  los_group, procedure_type;