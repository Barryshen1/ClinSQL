WITH 
troponin_t_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Troponin T%'
),
relevant_admissions AS (
  SELECT a.hadm_id, p.subject_id, p.anchor_age, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 84 AND 94
  AND a.hadm_id IN (
    SELECT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_version = 9 AND icd_code LIKE '786.5%'  
    OR icd_version = 10 AND icd_code LIKE 'R07%'
  )
),
first_troponin_t AS (
  SELECT l.hadm_id, l.valuenum, ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN troponin_t_itemid t ON l.itemid = t.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM relevant_admissions)
),
classified_troponin_t AS (
  SELECT hadm_id, valuenum,
  CASE 
    WHEN valuenum < 0.01 THEN 'normal'  
    WHEN valuenum BETWEEN 0.01 AND 0.03 THEN 'borderline'  
    ELSE 'elevated'
  END AS troponin_t_level
  FROM first_troponin_t
  WHERE rn = 1
)
SELECT 
  ctt.troponin_t_level,
  COUNT(*) as count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () as percentage,
  SUM(ra.hospital_expire_flag) as in_hospital_mortality_count,
  SUM(ra.hospital_expire_flag) * 100.0 / COUNT(*) as in_hospital_mortality_percentage
FROM classified_troponin_t ctt
INNER JOIN relevant_admissions ra ON ctt.hadm_id = ra.hadm_id
GROUP BY ctt.troponin_t_level
ORDER BY ctt.troponin_t_level;