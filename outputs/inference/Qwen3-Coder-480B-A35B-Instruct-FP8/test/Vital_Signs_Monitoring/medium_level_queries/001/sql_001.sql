WITH sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' AND LOWER(label) LIKE '%bp%'
),
sbp_first24 AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN sbp_items sbp
    ON ce.itemid = sbp.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY ce.subject_id, ce.stay_id
),
cohort AS (
  SELECT
    p.subject_id,
    s.stay_id,
    s.avg_sbp
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN sbp_first24 s
    ON p.subject_id = s.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
)
SELECT
  CASE
    WHEN avg_sbp < 140 THEN '<140'
    WHEN avg_sbp >= 140 AND avg_sbp <= 159 THEN '140–159'
    WHEN avg_sbp >= 160 THEN '≥160'
  END AS sbp_category,
  COUNT(DISTINCT subject_id) AS patient_count
FROM cohort
GROUP BY sbp_category
ORDER BY sbp_category;