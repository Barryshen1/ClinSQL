WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON adm.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = icu.subject_id
  WHERE LOWER(pat.gender) = 'f'
    AND pat.anchor_age BETWEEN 51 AND 61
),
instability_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%instability%'
),
instability_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MAX(ce.valuenum) AS instability_value
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN instability_items AS ii ON ce.itemid = ii.itemid
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
percentile_80 AS (
  SELECT
    100.0 * SUM(CASE WHEN instability_value <= 80 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_80
  FROM instability_scores
),
decile_top AS (
  SELECT AVG(ic.los) AS avg_icu_los_hours,
         SAFE_DIVIDE(SUM(CASE WHEN adm.hospital_expire_flag = 1 OR adm.deathtime IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate
  FROM (
    SELECT s.subject_id, s.hadm_id, s.stay_id, s.instability_value,
           NTILE(10) OVER (ORDER BY s.instability_value DESC) AS decile
    FROM instability_scores s
    WHERE s.instability_value IS NOT NULL
  ) AS d
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON ic.subject_id = d.subject_id
   AND ic.hadm_id = d.hadm_id
   AND ic.stay_id = d.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON adm.hadm_id = ic.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = ic.subject_id
  WHERE d.decile = 1
)
SELECT
  percentile_80.percentile_80 AS percentile_80,
  decile_top.avg_icu_los_hours,
  decile_top.mortality_rate
FROM percentile_80
CROSS JOIN decile_top;