WITH eligible AS (
  -- Men aged 86 to 96
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
counts_raw AS (
  -- Count distinct catheter ablation or cardioversion procedures per subject
  SELECT pi.subject_id,
         COUNT(DISTINCT CONCAT(CAST(pi.hadm_id AS STRING), '|', pi.icd_code, '|', CAST(pi.icd_version AS STRING))) AS cnt
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ablation%'
     OR LOWER(d.long_title) LIKE '%cardioversion%'
  GROUP BY pi.subject_id
),
counts_with_zero AS (
  -- Include patients with zero such procedures
  SELECT e.subject_id, COALESCE(n.cnt, 0) AS cnt
  FROM eligible e
  LEFT JOIN counts_raw n ON e.subject_id = n.subject_id
)
SELECT STDDEV_SAMP(cnt) AS sd_per_patient
FROM counts_with_zero;