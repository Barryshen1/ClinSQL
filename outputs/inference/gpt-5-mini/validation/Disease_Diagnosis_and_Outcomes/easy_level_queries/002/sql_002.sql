WITH primary_aki_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND (
      (d.icd_version = 9  AND STARTS_WITH(d.icd_code, '584'))  -- ICD-9 acute renal failure
      OR
      (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'N17'))   -- ICD-10 acute renal failure
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)

SELECT
  COUNT(*) AS n_admissions,
  APPROX_QUANTILES(p.los_days, 100)[OFFSET(75)] AS pct75_los_days
FROM primary_aki_admissions p
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE pt.gender = 'M'
  AND pt.anchor_age BETWEEN 52 AND 62;