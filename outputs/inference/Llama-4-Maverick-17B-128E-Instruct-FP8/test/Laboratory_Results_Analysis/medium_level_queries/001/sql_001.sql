WITH ami_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
  AND dicd.long_title LIKE '%Acute myocardial infarction%'
),
troponin_t_measurements AS (
  SELECT l.subject_id, l.hadm_id, l.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label LIKE '%Troponin T%' AND l.hadm_id IN (SELECT hadm_id FROM ami_patients)
),
categorized_troponin AS (
  SELECT subject_id, hadm_id, valuenum,
         CASE 
           WHEN valuenum < 0.01 THEN 'normal'  
           WHEN valuenum BETWEEN 0.01 AND 0.03 THEN 'borderline'  
           ELSE 'elevated'
         END AS troponin_category
  FROM troponin_t_measurements
  WHERE rn = 1  
)
SELECT troponin_category, COUNT(*) as count
FROM categorized_troponin
GROUP BY troponin_category;