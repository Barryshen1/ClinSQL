WITH acs_patients AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND d.icd_code LIKE 'I21%' 
     OR d.icd_code LIKE 'I22%'
),
troponin_observations AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl ON le.itemid = dl.itemid
  WHERE dl.label = 'Troponin T'
    AND le.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT hadm_id, valuenum
  FROM troponin_observations
  WHERE rn = 1
),
categorized AS (
  SELECT
    CASE
      WHEN valuenum <= 0.014 THEN 'Normal'
      WHEN valuenum <= 0.050 THEN 'Borderline'
      ELSE 'Elevated'
    END AS category
  FROM first_troponin
  WHERE hadm_id IN (SELECT hadm_id FROM acs_patients)
)
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized
GROUP BY category
ORDER BY category;