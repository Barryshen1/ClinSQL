WITH spo2_itemids AS (
  -- identify likely SpO2 / oxygen saturation itemids by text matching
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (
    LOWER(label) LIKE '%spo2%'
    OR LOWER(label) LIKE '%oxygen saturation%'
    OR LOWER(label) LIKE '%oxygen sat%'
    OR LOWER(label) LIKE '%o2 sat%'
    OR LOWER(abbreviation) LIKE '%spo2%'
    OR LOWER(abbreviation) LIKE '%o2sat%'
  )
),
spo2_first24 AS (
  -- all SpO2 numeric measurements in the first 24 hours of each ICU stay
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.itemid,
    ce.valuenum,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN spo2_itemids di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    -- first 24 hours window (inclusive of intime, exclusive of intime + 24h)
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    -- restrict to plausible SpO2 range to reduce obvious measurement errors
    AND ce.valuenum BETWEEN 50 AND 100
),
stay_avg AS (
  -- per-stay average SpO2 using first-24h measurements
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(valuenum) AS avg_spo2
  FROM spo2_first24
  GROUP BY subject_id, hadm_id, stay_id
),
aki_per_hadm AS (
  -- flag admissions with an AKI diagnosis by searching diagnosis long_title text
  SELECT DISTINCT d.hadm_id, TRUE AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
   AND d.icd_version = dic.icd_version
  WHERE LOWER(COALESCE(dic.long_title, '')) LIKE '%acute kidney%'
     OR LOWER(COALESCE(dic.long_title, '')) LIKE '%acute renal%'
),
cohort AS (
  -- restrict to female patients age 90-100 and attach AKI flag
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.avg_spo2,
    p.gender,
    p.anchor_age,
    IF(a.has_aki IS TRUE, 1, 0) AS aki_flag
  FROM stay_avg s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  LEFT JOIN aki_per_hadm a
    ON s.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
)
-- aggregate by SpO2 bins
SELECT
  bin,
  COUNT(*) AS n_stays,
  ROUND(AVG(avg_spo2), 2) AS mean_avg_spo2,
  ROUND(APPROX_QUANTILES(avg_spo2, 100)[OFFSET(50)], 2) AS median_avg_spo2,
  ROUND(APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)], 2) AS q1_avg_spo2,
  ROUND(APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)], 2) AS q3_avg_spo2,
  ROUND(
    (APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)]),
    2
  ) AS iqr_avg_spo2,
  ROUND(SUM(aki_flag) / COUNT(*), 3) AS aki_rate
FROM (
  SELECT
    *,
    CASE
      WHEN avg_spo2 < 90 THEN '<90'
      WHEN avg_spo2 >= 90 AND avg_spo2 <= 92 THEN '90-92'
      WHEN avg_spo2 >= 93 AND avg_spo2 <= 95 THEN '93-95'
      WHEN avg_spo2 > 95 THEN '>95'
      ELSE 'unknown'
    END AS bin
  FROM cohort
)
GROUP BY bin
ORDER BY
  -- order bins meaningfully
  CASE bin
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
    ELSE 5
  END;