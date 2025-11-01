WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
),
los_bins AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_bin
  FROM cohort
),
icu_status AS (
  SELECT
    hadm_id,
    1 AS icu_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
noninvasive_procs AS (
  SELECT
    proc.subject_id,
    proc.hadm_id,
    proc.icd_code,
    proc.icd_version,
    dproc.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
      ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE
    REGEXP_CONTAINS(LOWER(dproc.long_title),
      r'(x-ray|ct|mri|ultrasound|imaging|radiology|electrocardiogram|ecg|ekg|eeg|electroencephalogram|pulmonary function|pft)')
),
admission_proc_counts AS (
  SELECT
    lb.hadm_id,
    COUNT(DISTINCT np.icd_code) AS num_noninvasive_procs
  FROM los_bins lb
    LEFT JOIN noninvasive_procs np
      ON lb.hadm_id = np.hadm_id
  GROUP BY lb.hadm_id
),
final AS (
  SELECT
    lb.hadm_id,
    lb.los_bin,
    COALESCE(icu.icu_admit, 0) AS icu_status,
    apc.num_noninvasive_procs
  FROM los_bins lb
    LEFT JOIN icu_status icu
      ON lb.hadm_id = icu.hadm_id
    LEFT JOIN admission_proc_counts apc
      ON lb.hadm_id = apc.hadm_id
  WHERE lb.los_bin IS NOT NULL
)
SELECT
  los_bin,
  icu_status,
  COUNT(*) AS num_admissions,
  AVG(COALESCE(num_noninvasive_procs, 0)) AS mean_num_noninvasive_diagnostics
FROM final
GROUP BY los_bin, icu_status
ORDER BY los_bin, icu_status;