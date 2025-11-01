WITH ami_diagnoses AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10 AND REGEXP_CONTAINS(long_title, r'.*Myocardial infarction.*')
),
ami_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON p.subject_id = di.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 76 AND 86
  AND di.icd_code IN (SELECT icd_code FROM ami_diagnoses)
  AND di.icd_version = 10
),
troponin_i AS (
  SELECT di.itemid, le.hadm_id, le.valuenum, ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE di.label LIKE '%Troponin-I%' AND le.hadm_id IN (SELECT hadm_id FROM ami_patients)
),
classified_troponin AS (
  SELECT hadm_id, valuenum,
  CASE
    WHEN valuenum <= 0.04 THEN 'Normal'
    WHEN valuenum BETWEEN 0.04 AND 0.40 THEN 'Borderline'
    ELSE 'Elevated'
  END AS troponin_level
  FROM troponin_i
  WHERE rn = 1
)
SELECT 
  troponin_level,
  COUNT(*) as count,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM classified_troponin) as percentage,
  AVG(valuenum) as mean,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] as median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] as q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] as q3
FROM classified_troponin
GROUP BY troponin_level
ORDER BY troponin_level;