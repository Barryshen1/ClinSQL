WITH 
eligible_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 48 AND 58
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_version = 10 AND icd_code LIKE 'E11%'
  )
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_version = 10 AND icd_code LIKE 'I50%'
  )
),

glp1_administrations AS (
  SELECT e.hadm_id, e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  WHERE LOWER(e.medication) LIKE '%liraglutide%' OR LOWER(e.medication) LIKE '%semaglutide%' 
),

first_12h_glp1 AS (
  SELECT ga.hadm_id, COUNT(*) as count_first_12h
  FROM glp1_administrations ga
  JOIN eligible_patients ep ON ga.hadm_id = ep.hadm_id
  WHERE ga.charttime <= TIMESTAMP_ADD(ep.admittime, INTERVAL 12 HOUR)
  GROUP BY ga.hadm_id
),

last_12h_glp1 AS (
  SELECT ga.hadm_id, COUNT(*) as count_last_12h
  FROM glp1_administrations ga
  JOIN eligible_patients ep ON ga.hadm_id = ep.hadm_id
  WHERE ga.charttime >= TIMESTAMP_SUB(ep.dischtime, INTERVAL 12 HOUR)
  GROUP BY ga.hadm_id
)

SELECT 
  COUNT(CASE WHEN f.count_first_12h > 0 THEN 1 END) / COUNT(DISTINCT ep.hadm_id) * 100 AS percent_first_12h,
  COUNT(CASE WHEN l.count_last_12h > 0 THEN 1 END) / COUNT(DISTINCT ep.hadm_id) * 100 AS percent_last_12h,
  (COUNT(CASE WHEN l.count_last_12h > 0 THEN 1 END) - COUNT(CASE WHEN f.count_first_12h > 0 THEN 1 END)) / COUNT(DISTINCT ep.hadm_id) * 100 AS net_change
FROM eligible_patients ep
LEFT JOIN first_12h_glp1 f ON ep.hadm_id = f.hadm_id
LEFT JOIN last_12h_glp1 l ON ep.hadm_id = l.hadm_id;