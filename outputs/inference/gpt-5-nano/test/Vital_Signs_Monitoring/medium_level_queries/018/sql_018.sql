WITH stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 75 AND 85
),
sbp_means AS (
  SELECT
    s.stay_id,
    AVG(cv.valuenum) AS mean_sbp_first_48
  FROM stays AS s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS cv
    ON cv.subject_id = s.subject_id
   AND cv.hadm_id = s.hadm_id
   AND cv.stay_id = s.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON cv.itemid = di.itemid
  WHERE cv.charttime >= s.intime
    AND cv.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.label) LIKE '%blood%'
  GROUP BY s.stay_id
)
SELECT
  COUNT(*) AS total_stays,
  SUM(CASE WHEN mean_sbp_first_48 <= 140 THEN 1 ELSE 0 END) AS le_140,
  SAFE_DIVIDE(
     SUM(CASE WHEN mean_sbp_first_48 <= 140 THEN 1 ELSE 0 END),
     COUNT(*)
  ) AS percentile_140
FROM sbp_means;