WITH spo2_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'spo2'
),
stay_ages AS (
  SELECT
    p.subject_id,
    i.stay_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 80 AND 90
),
spo2_per_stay AS (
  SELECT
    s.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM stay_ages s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.stay_id = ce.stay_id
  CROSS JOIN spo2_item si
  WHERE ce.itemid = si.itemid
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
  GROUP BY s.stay_id
  HAVING AVG(ce.valuenum) IS NOT NULL
),
percentile_calc AS (
  SELECT
    COUNT(*) AS total_stays,
    COUNT(CASE WHEN avg_spo2 <= 88 THEN 1 END) AS stays_with_avg_spo2_lte_88
  FROM spo2_per_stay
)
SELECT
  SAFE_DIVIDE(stays_with_avg_spo2_lte_88 * 100.0, total_stays) AS percentile
FROM percentile_calc;