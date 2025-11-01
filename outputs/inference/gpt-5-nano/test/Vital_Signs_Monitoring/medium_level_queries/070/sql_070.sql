WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
     OR LOWER(label) LIKE '%oxygen saturation%'
     OR LOWER(label) LIKE '%o2 sat%'
),
-- Per-stay average SpO2 in first 24 hours for female patients aged 90-100
spo2_by_stay AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    AVG(ce.valuenum) AS spo2_avg
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
  JOIN spo2_items AS s ON ce.itemid = s.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'Female'
    AND p.anchor_age >= 90
    AND p.anchor_age <= 100
  GROUP BY i.stay_id, i.hadm_id, i.subject_id
),
-- AKI flags per stay (ICD-9 584% and ICD-10 N17%)
aki_by_stay AS (
  SELECT
    s.stay_id,
    MAX(CASE WHEN d.icd_code LIKE '584%' AND d.icd_version = 9 THEN 1 ELSE 0 END) AS aki_flag9,
    MAX(CASE WHEN d.icd_code LIKE 'N17%' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS aki_flag10
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON s.subject_id = d.subject_id
   AND s.hadm_id = d.hadm_id
  GROUP BY s.stay_id
),
aki_final AS (
  -- AKI present if either ICD-9 or ICD-10 flag is 1
  SELECT stay_id,
         CASE WHEN COALESCE(aki_flag9, 0) = 1 OR COALESCE(aki_flag10, 0) = 1 THEN 1 ELSE 0 END AS aki_flag
  FROM aki_by_stay
),
combined AS (
  SELECT
    sp.stay_id,
    sp.hadm_id,
    sp.subject_id,
    sp.spo2_avg,
    a.aki_flag
  FROM spo2_by_stay AS sp
  LEFT JOIN aki_final AS a
    ON sp.stay_id = a.stay_id
),
spo2_bins AS (
  SELECT
    CASE
      WHEN spo2_avg < 90 THEN '<90'
      WHEN spo2_avg BETWEEN 90 AND 92 THEN '90-92'
      WHEN spo2_avg BETWEEN 93 AND 95 THEN '93-95'
      WHEN spo2_avg > 95 THEN '>95'
    END AS spo2_bin,
    spo2_avg,
    aki_flag
  FROM combined
  WHERE spo2_avg IS NOT NULL
),
per_bin AS (
  SELECT
     spo2_bin,
     COUNT(*) AS N,
     AVG(spo2_avg) AS mean_spo2,
     AVG(aki_flag) AS aki_rate,
     APPROX_QUANTILES(spo2_avg, 100) AS qa
  FROM spo2_bins
  GROUP BY spo2_bin
)
SELECT
  spo2_bin,
  N,
  mean_spo2,
  qa[OFFSET(50)] AS median_spo2,
  qa[OFFSET(25)] AS q1_spo2,
  qa[OFFSET(75)] AS q3_spo2,
  aki_rate
FROM per_bin
ORDER BY spo2_bin;