WITH uti_index AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
    AND adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND adm.insurance = 'Medicare'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND UPPER(adm.admission_location) LIKE '%EMERGENCY%'
    AND dx.seq_num = 1
    AND (
         -- ICD-9
         (dx.icd_version = 9 AND (
             dx.icd_code LIKE '5990%' OR  -- UTI NOS
             dx.icd_code LIKE '590%'  OR  -- Pyelonephritis
             dx.icd_code LIKE '595%'     -- Cystitis
         ))
         OR
         -- ICD-10
         (dx.icd_version = 10 AND (
             dx.icd_code LIKE 'N39.0%' OR -- UTI NOS
             dx.icd_code LIKE 'N10%'  OR  -- Acute pyelonephritis
             dx.icd_code LIKE 'N30%'      -- Cystitis
         ))
       )
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
next_admit AS (
  SELECT
    idx.subject_id,
    idx.hadm_id,
    idx.admittime,
    idx.dischtime,
    idx.los_days,
    MIN(adm2.admittime) AS next_admittime
  FROM uti_index idx
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm2
    ON idx.subject_id = adm2.subject_id
    AND adm2.admittime > idx.dischtime
  GROUP BY idx.subject_id, idx.hadm_id, idx.admittime, idx.dischtime, idx.los_days
),
flagged AS (
  SELECT
    *,
    CASE
      WHEN next_admittime IS NOT NULL
           AND TIMESTAMP_DIFF(next_admittime, dischtime, DAY) <= 30
      THEN 1 ELSE 0
    END AS readmit_flag
  FROM next_admit
)
SELECT
  readmit_flag,
  COUNT(*) AS n_patients,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  100.0 * SUM(CASE WHEN los_days > 9 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_gt9
FROM flagged
GROUP BY readmit_flag
ORDER BY readmit_flag DESC;