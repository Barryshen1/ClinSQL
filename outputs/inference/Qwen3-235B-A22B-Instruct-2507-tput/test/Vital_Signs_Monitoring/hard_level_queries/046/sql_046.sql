WITH cohort AS (
  SELECT DISTINCT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime,
    s.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON s.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age) BETWEEN 84 AND 94
    AND (
      (dd.icd_version = 10 AND dd.icd_code LIKE 'I63%') OR
      (dd.icd_version = 9 AND dd.icd_code LIKE '434%')
    )
),
vital_signs_abnormal AS (
  SELECT
    ce.stay_id,
    CASE
      WHEN di.label LIKE '%heart rate%' AND (ce.valuenum < 50 OR ce.valuenum > 100) THEN 1
      WHEN di.label LIKE '%systolic%' AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
      WHEN di.label LIKE '%resp%' AND (ce.valuenum < 10 OR ce.valuenum > 25) THEN 1
      WHEN LOWER(di.label) LIKE '%spo2%' AND ce.valuenum < 92 THEN 1
      WHEN LOWER(di.label) LIKE '%temp%' AND (ce.valuenum < 36 OR ce.valuenum > 38) THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  INNER JOIN cohort c
    ON ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND di.category = 'Vital Signs'
    AND ce.valuenum IS NOT NULL
),
instability_score AS (
  SELECT
    stay_id,
    SUM(is_abnormal) AS instability_score
  FROM vital_signs_abnormal
  GROUP BY stay_id
),
score_percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 1000) AS quantiles
  FROM instability_score
),
percentile_of_80 AS (
  SELECT
    quantiles[OFFSET(750)] AS q75,
    (SELECT APPROX_COUNT_DISTINCT(instability_score) FROM instability_score WHERE instability_score <= 80) * 1.0 / COUNT(*) AS percentile_of_80
  FROM score_percentiles
),
top_quartile_outcomes AS (
  SELECT
    AVG(c.icu_los) AS avg_icu_los_top_quartile,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate_top_quartile
  FROM cohort c
  INNER JOIN instability_score s ON c.stay_id = s.stay_id
  CROSS JOIN percentile_of_80 p
  WHERE s.instability_score >= p.q75
)
SELECT
  (SELECT percentile_of_80 FROM percentile_of_80) AS percentile_of_score_80,
  (SELECT avg_icu_los_top_quartile FROM top_quartile_outcomes) AS avg_icu_los_top_quartile,
  (SELECT mortality_rate_top_quartile FROM top_quartile_outcomes) AS mortality_rate_top_quartile;