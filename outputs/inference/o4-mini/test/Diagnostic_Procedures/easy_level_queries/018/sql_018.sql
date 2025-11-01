WITH cohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
  GROUP BY
    p.subject_id
),
pt_procs AS (
  SELECT
    c.subject_id,
    -- count each distinct procedure line once: hadm_id + seq_num
    COUNT(DISTINCT CONCAT(pr.hadm_id, '_', pr.seq_num)) AS proc_count
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON c.subject_id = pr.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code = dp.icd_code
     AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ablation%'
    OR LOWER(dp.long_title) LIKE '%cardioversion%'
  GROUP BY
    c.subject_id
)
SELECT
  STDDEV_SAMP(proc_count) AS sd_procedures_per_patient
FROM
  pt_procs;