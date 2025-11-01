WITH male_icu_stays AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
resp_rate_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%respiratory rate%'
    AND LOWER(category) LIKE '%vital signs%'
),
stay_avg_rr AS (
  SELECT 
    s.stay_id,
    AVG(ce.valuenum) AS avg_rr_48h
  FROM male_icu_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON s.stay_id = ce.stay_id
  INNER JOIN resp_rate_items rri
    ON ce.itemid = rri.itemid
  WHERE ce.charttime >= s.intime
    AND ce.charttime <= DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- physiologically plausible
  GROUP BY s.stay_id
)
SELECT
  SAFE_DIVIDE(
    COUNTIF(avg_rr_48h <= 12),
    COUNT(*)
  ) AS percentile_rank_of_12
FROM stay_avg_rr;