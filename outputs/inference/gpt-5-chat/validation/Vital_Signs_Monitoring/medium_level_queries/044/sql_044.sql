WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),
sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE 'systolic blood pressure%'
),
sbp_first48 AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN sbp_items di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
)
SELECT
  150 AS target_sbp,
  -- median using approx_quantiles
  APPROX_QUANTILES(avg_sbp, 100)[OFFSET(50)] AS median_sbp_in_group,
  -- percentile of target
  AVG(CASE WHEN avg_sbp <= 150 THEN 1 ELSE 0 END) * 100 AS percentile_of_target
FROM sbp_first48;