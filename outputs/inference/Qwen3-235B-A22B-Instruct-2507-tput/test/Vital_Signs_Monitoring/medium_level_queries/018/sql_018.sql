WITH female_icu_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 75 AND 85
),
systolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(linksto) = 'chartevents'
),
stay_sbp_mean AS (
  SELECT
    f.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM female_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON f.stay_id = ce.stay_id
  JOIN systolic_bp_items s
    ON ce.itemid = s.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= f.intime
    AND ce.charttime <= DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
    AND ce.valuenum > 0  -- reasonable SBP range, avoid errors
    AND ce.valuenum < 300
  GROUP BY f.stay_id
)
SELECT
  ROUND(
    COUNTIF(mean_sbp <= 140) * 100.0 / COUNT(*), 
    2
  ) AS percentile_of_140
FROM stay_sbp_mean;