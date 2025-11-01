WITH spo2_by_stay AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    AVG(ce.valuenum) AS spo2_avg
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
   AND icu.hadm_id = ce.hadm_id
   AND icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE di.label LIKE '%SpO2%'
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id, icu.subject_id, icu.hadm_id
),

-- 2) Filter to target cohort: female, age 80-90
cohort AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.spo2_avg
  FROM spo2_by_stay AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
)

-- 3) Compute the percentile of 88% within the cohort
SELECT
  100.0 * SUM(CASE WHEN spo2_avg <= 88 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_88
FROM cohort;