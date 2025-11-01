WITH postop AS (
  -- admissions with a postoperative complication diagnosis (ICD-9 '998%')
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 9
    AND icd_code LIKE '998%'
),
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- ICU vs non-ICU
    CASE
      WHEN icu.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'non-ICU'
    END AS unit,
    -- length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- time-to-death in days (only for those who died in hospital)
    CASE 
      WHEN a.hospital_expire_flag = 1 
      THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
      ELSE NULL
    END AS ttd_days,
    -- placeholder for Charlson score (to be computed separately)
    NULL AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON a.hadm_id = icu.hadm_id
  JOIN postop
    ON a.subject_id = postop.subject_id
   AND a.hadm_id    = postop.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
buckets AS (
  SELECT
    unit,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8         THEN '8+'
      ELSE '0'
    END AS los_bucket,
    CASE
      WHEN charlson_score <= 3           THEN '≤3'
      WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
      WHEN charlson_score > 5            THEN '>5'
      ELSE 'Unknown'
    END AS charlson_bucket,
    hospital_expire_flag,
    ttd_days
  FROM base
)
SELECT
  unit,
  los_bucket,
  charlson_bucket,
  COUNT(*) AS N,
  100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_pct,
  -- median time-to-death among those who died (approximate)
  APPROX_QUANTILES(ttd_days, 2)[OFFSET(1)] AS median_ttd_days
FROM buckets
WHERE ttd_days IS NOT NULL
GROUP BY unit, los_bucket, charlson_bucket
ORDER BY unit, los_bucket, charlson_bucket;