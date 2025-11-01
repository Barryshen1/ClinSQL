WITH 
hs_troponin_t AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%hs-Troponin T%' 
),
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 64 AND 74
),
first_hs_troponin AS (
  SELECT ep.subject_id, ep.hadm_id, le.valuenum,
         ROW_NUMBER() OVER (PARTITION BY ep.hadm_id ORDER BY le.charttime) AS rn
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ep.hadm_id = le.hadm_id
  INNER JOIN hs_troponin_t htt ON le.itemid = htt.itemid
),
elevated_troponin AS (
  SELECT subject_id, hadm_id
  FROM first_hs_troponin
  WHERE rn = 1 AND valuenum > 0.026
),
mortality AS (
  SELECT et.hadm_id, 
         CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS in_hospital_mortality
  FROM elevated_troponin et
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON et.hadm_id = a.hadm_id
)
SELECT 
  COUNT(*) AS total_patients,
  AVG(anchor_age) AS mean_age,
  STDDEV(anchor_age) AS std_age,
  MIN(anchor_age) AS min_age,
  MAX(anchor_age) AS max_age,
  SUM(in_hospital_mortality) / COUNT(*) AS in_hospital_mortality_rate
FROM (
  SELECT DISTINCT et.subject_id, et.hadm_id, ep.anchor_age, m.in_hospital_mortality
  FROM elevated_troponin et
  INNER JOIN eligible_patients ep ON et.subject_id = ep.subject_id AND et.hadm_id = ep.hadm_id
  INNER JOIN mortality m ON et.hadm_id = m.hadm_id
);