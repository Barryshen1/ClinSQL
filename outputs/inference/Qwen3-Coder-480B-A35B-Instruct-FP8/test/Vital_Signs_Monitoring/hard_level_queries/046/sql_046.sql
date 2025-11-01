WITH vitals_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'heart rate', 'sbp', 'dbp', 'respiratory rate', 'temperature fahrenheit',
    'o2 saturation', 'spo2'
  )
),
stroke_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ischemic stroke%'
),
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
),
icu_stays_filtered AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN stroke_admissions sa ON icu.hadm_id = sa.hadm_id
  JOIN eligible_patients ep ON icu.subject_id = ep.subject_id
),
vital_sign_scores AS (
  SELECT
    icu.stay_id,
    SUM(
      CASE
        WHEN LOWER(d.label) = 'heart rate' AND (ce.valuenum > 130 OR ce.valuenum < 50) THEN 1
        WHEN LOWER(d.label) IN ('sbp', 'dbp') AND (ce.valuenum > 180 OR ce.valuenum < 90) THEN 1
        WHEN LOWER(d.label) = 'respiratory rate' AND (ce.valuenum > 30 OR ce.valuenum < 10) THEN 1
        WHEN LOWER(d.label) = 'temperature fahrenheit' AND (ce.valuenum > 101.3 OR ce.valuenum < 95.9) THEN 1
        WHEN LOWER(d.label) IN ('o2 saturation', 'spo2') AND ce.valuenum < 90 THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM icu_stays_filtered icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  JOIN vitals_items d ON ce.itemid = d.itemid
  WHERE ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
),
score_percentiles AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank
  FROM vital_sign_scores
),
score_80_percentile AS (
  SELECT MAX(percentile_rank) AS percentile_of_80
  FROM score_percentiles
  WHERE instability_score = 80
),
top_quartile AS (
  SELECT *
  FROM score_percentiles
  WHERE percentile_rank >= 0.75
)
SELECT
  (SELECT percentile_of_80 FROM score_80_percentile) AS percentile_of_score_80,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_top_quartile,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_top_quartile
FROM top_quartile t
JOIN icu_stays_filtered icu ON t.stay_id = icu.stay_id;