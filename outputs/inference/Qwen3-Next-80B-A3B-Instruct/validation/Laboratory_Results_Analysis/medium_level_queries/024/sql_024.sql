WITH first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS first_troponin_t,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.labevents l
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE 
    LOWER(d.label) LIKE '%troponin%t%' 
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
),
chest_pain_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    d.seq_num = 1
    AND (
      di.icd_code IN ('R07.9', 'R07.89', 'R07.1', 'R07.2')
      OR LOWER(di.long_title) LIKE '%chest pain%'
    )
)
SELECT 
  COUNT(*) AS total_patients,
  AVG(ft.first_troponin_t) AS mean_first_troponin_t,
  APPROX_QUANTILES(ft.first_troponin_t, 100)[OFFSET(50)] AS median_first_troponin_t,
  AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
FROM 
  physionet-data.mimiciv_3_1_hosp.patients p
INNER JOIN 
  physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
INNER JOIN 
  chest_pain_admissions cp
  ON a.hadm_id = cp.hadm_id
INNER JOIN 
  first_troponin ft
  ON a.hadm_id = ft.hadm_id AND ft.rn = 1
WHERE 
  p.gender = 'M'
  AND p.anchor_age BETWEEN 64 AND 74
  AND ft.first_troponin_t > 14;