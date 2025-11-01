WITH asthma_admissions AS (
  -- Admissions for female patients age 88-98 that have an asthma diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS stay_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- require at least one diagnosis row whose description indicates asthma
  JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
      ON d.icd_code = dic.icd_code
     AND d.icd_version = dic.icd_version
    WHERE LOWER(dic.long_title) LIKE '%asthma%'
  ) ast
    ON a.hadm_id = ast.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- restrict to stays 1-7 days (we will split into 1-3 and 4-7)
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

procedures_per_admission AS (
  -- Count diagnostic procedures per admission (zero if none)
  SELECT
    aa.hadm_id,
    aa.stay_days,
    COUNT(DISTINCT CASE
      WHEN LOWER(dip.long_title) LIKE '%diagnos%' THEN proc.seq_num
      ELSE NULL END) AS diag_proc_count
  FROM asthma_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON aa.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON proc.icd_code = dip.icd_code
   AND proc.icd_version = dip.icd_version
  GROUP BY aa.hadm_id, aa.stay_days
)

SELECT
  '1-3 days' AS stay_group,
  quantiles[OFFSET(1)] AS p25_diag_procs,
  quantiles[OFFSET(2)] AS p50_diag_procs,
  quantiles[OFFSET(3)] AS p75_diag_procs,
  n_admissions
FROM (
  SELECT
    APPROX_QUANTILES(diag_proc_count, 4) AS quantiles,
    COUNT(*) AS n_admissions
  FROM procedures_per_admission
  WHERE stay_days BETWEEN 1 AND 3
)
UNION ALL
SELECT
  '4-7 days' AS stay_group,
  quantiles[OFFSET(1)] AS p25_diag_procs,
  quantiles[OFFSET(2)] AS p50_diag_procs,
  quantiles[OFFSET(3)] AS p75_diag_procs,
  n_admissions
FROM (
  SELECT
    APPROX_QUANTILES(diag_proc_count, 4) AS quantiles,
    COUNT(*) AS n_admissions
  FROM procedures_per_admission
  WHERE stay_days BETWEEN 4 AND 7
);