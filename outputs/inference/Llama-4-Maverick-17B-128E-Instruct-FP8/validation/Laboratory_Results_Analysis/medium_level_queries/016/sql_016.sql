WITH 
troponin_t_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%'
),
relevant_admissions AS (
  SELECT a.hadm_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 79 AND 89
),
first_troponin_t AS (
  SELECT l.hadm_id, l.valuenum,
         ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN troponin_t_itemid t ON l.itemid = t.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM relevant_admissions)
),
categorized_troponin_t AS (
  SELECT hadm_id, valuenum,
         CASE
           WHEN valuenum < 0.01 THEN 'normal'
           WHEN valuenum <= 0.03 THEN 'borderline'
           ELSE 'elevated'
         END AS category
  FROM first_troponin_t
  WHERE rn = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_troponin_t) AS percentage,
  AVG(valuenum) AS mean,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3
FROM categorized_troponin_t
GROUP BY category;