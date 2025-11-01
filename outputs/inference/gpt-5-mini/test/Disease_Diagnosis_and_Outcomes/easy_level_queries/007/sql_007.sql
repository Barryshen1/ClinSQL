WITH primary_ugib AS (
  SELECT d.subject_id,
         d.hadm_id,
         LOWER(di.long_title) AS diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    USING(icd_code, icd_version)
  WHERE d.seq_num = 1
    AND (
      LOWER(di.long_title) LIKE '%upper gastrointestinal hemorrhage%'
      OR LOWER(di.long_title) LIKE '%upper gastrointestinal bleeding%'
      OR LOWER(di.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(di.long_title) LIKE '%hemorrhage of gastrointestinal tract%'
      OR LOWER(di.long_title) LIKE '%bleeding peptic ulcer%'
      OR LOWER(di.long_title) LIKE '%peptic ulcer with hemorrhage%'
      OR LOWER(di.long_title) LIKE '%duodenal ulcer with hemorrhage%'
      OR LOWER(di.long_title) LIKE '%gastric ulcer with hemorrhage%'
      OR LOWER(di.long_title) LIKE '%hemorrhag%'    -- broad fallback for "hemorrhage"/"haemorrhage" stems
    )
)

SELECT
  COUNT(*) AS n_patients,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS pct25_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS pct75_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)]
    - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr_days
FROM (
  SELECT a.subject_id,
         a.hadm_id,
         -- LOS in fractional days (preserves sub-day precision)
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN primary_ugib pu
    USING(subject_id, hadm_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
);