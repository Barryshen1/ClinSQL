WITH 
acs_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE icd_version = 10 AND icd_code LIKE 'I21%' 
     OR icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '411%')
),
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 67 AND 77
    AND a.hadm_id IN (SELECT hadm_id FROM acs_admissions)
),
troponin_t AS (
  SELECT ep.hadm_id, le.valuenum, ROW_NUMBER() OVER (PARTITION BY ep.hadm_id ORDER BY le.charttime) as rn
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le ON ep.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dli ON le.itemid = dli.itemid
  WHERE dli.label LIKE '%Troponin T%'
),
categorized_troponin AS (
  SELECT hadm_id, 
         CASE 
           WHEN valuenum <= 0.04 THEN 'normal'
           WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'borderline'
           ELSE 'elevated'
         END AS troponin_category,
         CASE 
           WHEN deathtime IS NOT NULL THEN 1
           ELSE 0
         END AS in_hospital_mortality
  FROM (
    SELECT t.hadm_id, t.valuenum, ep.deathtime
    FROM troponin_t t
    INNER JOIN eligible_patients ep ON t.hadm_id = ep.hadm_id
    WHERE t.rn = 1
  )
)
SELECT 
  troponin_category,
  COUNT(*) as count,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_troponin) as percent_of_admissions,
  AVG(in_hospital_mortality) as in_hospital_mortality_rate
FROM categorized_troponin
GROUP BY troponin_category
ORDER BY troponin_category;