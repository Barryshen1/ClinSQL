WITH dialysis_admissions AS (
  -- admissions that have at least one ICD procedure whose description mentions "dialysis"
  SELECT DISTINCT proc.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON proc.icd_code = d.icd_code
   AND proc.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%dialysis%'
)

SELECT
  COUNT(DISTINCT a.hadm_id) AS n_encounters,
  STDDEV_SAMP(
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0
  ) AS sd_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN dialysis_admissions da
  ON a.hadm_id = da.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 44 AND 54
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  -- ensure non-negative LOS
  AND TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) >= 0;