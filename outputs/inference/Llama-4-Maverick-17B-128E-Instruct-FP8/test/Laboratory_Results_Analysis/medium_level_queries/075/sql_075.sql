WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 41 AND 51
),
admissions_filtered AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE a.admission_type LIKE '%EMERGENCY%' OR a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'I21%'  
  )
),
troponin_t AS (
  SELECT a.hadm_id, l.valuenum, ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) as rn
  FROM admissions_filtered a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  WHERE l.itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label LIKE '%Troponin T%' LIMIT 1)
),
troponin_t_category AS (
  SELECT hadm_id, valuenum,
    CASE
      WHEN valuenum < 0.01 THEN 'normal'  
      WHEN valuenum BETWEEN 0.01 AND 0.03 THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM troponin_t
  WHERE rn = 1
)
SELECT 
  category,
  COUNT(*) as count,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM troponin_t_category) as percentage,
  AVG(valuenum) as mean,
  PERCENTILE_CONT(valuenum, 0.5) AS median,
  PERCENTILE_CONT(valuenum, 0.25) AS q1,
  PERCENTILE_CONT(valuenum, 0.75) AS q3
FROM troponin_t_category
GROUP BY category;