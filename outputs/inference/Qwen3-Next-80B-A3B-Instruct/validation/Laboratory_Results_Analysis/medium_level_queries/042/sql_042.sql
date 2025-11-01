WITH chest_pain_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%chest pain%'
),
female_84_94 AS (
  SELECT p.subject_id, p.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 84 AND 94
),
troponin_t_first AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum >= 0
),
filtered_troponin AS (
  SELECT 
    t.hadm_id,
    t.valuenum,
    CASE 
      WHEN t.valuenum <= 0.04 THEN 'normal'
      WHEN t.valuenum <= 0.10 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM troponin_t_first t
  JOIN chest_pain_admissions cp ON t.hadm_id = cp.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON t.hadm_id = a.hadm_id
  JOIN female_84_94 f ON a.subject_id = f.subject_id
  WHERE t.rn = 1
)
SELECT 
  ft.troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_count,
  ROUND(100.0 * SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_percentage
FROM filtered_troponin ft
JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON ft.hadm_id = a.hadm_id
GROUP BY ft.troponin_category
ORDER BY ft.troponin_category;