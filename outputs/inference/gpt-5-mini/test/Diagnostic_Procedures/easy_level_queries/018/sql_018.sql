WITH cohort AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),

proc_codes AS (
  -- ICD procedure codes whose description suggests catheter ablation or cardioversion
  SELECT
    icd_code,
    icd_version,
    long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    -- match ablation (ablat) or cardioversion (cardioversion) in a case-insensitive way
    REGEXP_CONTAINS(LOWER(COALESCE(long_title, '')), r'ablat|cardioversion')
),

patient_procs AS (
  -- procedure records (joined to descriptive titles)
  SELECT
    p.subject_id,
    p.hadm_id,
    p.seq_num,
    p.icd_code,
    p.icd_version,
    dp.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    proc_codes dp
  ON
    p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
),

counts_per_patient AS (
  -- count distinct procedure records per patient (deduplicating by hadm_id + seq_num + icd_code)
  SELECT
    subject_id,
    COUNT(DISTINCT CONCAT(CAST(hadm_id AS STRING), '-', CAST(seq_num AS STRING), '-', COALESCE(icd_code, ''))) AS proc_count
  FROM
    patient_procs
  GROUP BY
    subject_id
),

all_counts AS (
  -- include patients with zero procedures
  SELECT
    c.subject_id,
    COALESCE(cp.proc_count, 0) AS proc_count
  FROM
    cohort c
  LEFT JOIN
    counts_per_patient cp
  ON
    c.subject_id = cp.subject_id
)

-- final: compute standard deviation of distinct procedures per patient
SELECT
  STDDEV_POP(proc_count) AS sd_distinct_ablation_or_cardioversion_per_patient,
  COUNT(*) AS n_patients,
  AVG(proc_count) AS mean_distinct_procs_per_patient
FROM
  all_counts;