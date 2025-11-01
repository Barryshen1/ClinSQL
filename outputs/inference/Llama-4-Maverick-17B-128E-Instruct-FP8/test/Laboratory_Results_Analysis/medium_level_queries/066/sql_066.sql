WITH 
hs_tnt_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%' AND label LIKE '%high sensitivity%'
),
relevant_admissions AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 39 AND 49
),
initial_hs_tnt AS (
  SELECT la.subject_id, la.hadm_id, la.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY la.hadm_id ORDER BY la.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` la
  INNER JOIN hs_tnt_itemid ON la.itemid = hs_tnt_itemid.itemid
  WHERE la.hadm_id IN (SELECT hadm_id FROM relevant_admissions)
),
categorized_hs_tnt AS (
  SELECT 
    CASE 
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum BETWEEN 14 AND 52 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS category,
    valuenum
  FROM initial_hs_tnt
  WHERE rn = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage,
  AVG(valuenum) AS mean,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3
FROM categorized_hs_tnt
GROUP BY category;