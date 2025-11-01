WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
target_procedures AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%ablation%'
     OR LOWER(long_title) LIKE '%cardioversion%'
),
patient_proc_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', CAST(proc.icd_version AS STRING))) AS num_distinct_procs
  FROM target_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN target_procedures tp
    ON proc.icd_code = tp.icd_code AND proc.icd_version = tp.icd_version
  WHERE tp.icd_code IS NOT NULL
  GROUP BY p.subject_id

  UNION ALL

  -- Patients with zero procedures (not matched above)
  SELECT
    p.subject_id,
    0 AS num_distinct_procs
  FROM target_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN target_procedures tp
    ON proc.icd_code = tp.icd_code AND proc.icd_version = tp.icd_version
  WHERE proc.subject_id IS NULL OR tp.icd_code IS NULL
    AND p.subject_id NOT IN (
      SELECT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc2
      JOIN target_procedures tp2
        ON proc2.icd_code = tp2.icd_code AND proc2.icd_version = tp2.icd_version
    )
)
SELECT
  STDDEV_SAMP(num_distinct_procs) AS sd_distinct_ablation_cardioversion_per_patient
FROM patient_proc_counts;