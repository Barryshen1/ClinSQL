WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 87 AND 97
),
acs_cohort AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.hospital_expire_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON c.hadm_id = diag.hadm_id
  WHERE diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code IN ('411.1', '411.81')))
      OR 
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'I20.0%' OR diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code LIKE 'I24%'))
    )
),
troponin_data AS (
  SELECT 
    l.hadm_id,
    l.charttime,
    CASE 
      WHEN l.valueuom = 'ng/L' THEN l.valuenum / 1000.0
      ELSE l.valuenum
    END AS troponin_t_ngml
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid IN (51003, 51749)  -- Troponin T and High-Sensitivity Troponin T
    AND l.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    td.hadm_id,
    td.troponin_t_ngml,
    ROW_NUMBER() OVER (PARTITION BY td.hadm_id ORDER BY td.charttime) AS rn
  FROM troponin_data td
  INNER JOIN acs_cohort ac ON td.hadm_id = ac.hadm_id
),
categorized_troponin AS (
  SELECT 
    ac.hadm_id,
    ac.hospital_expire_flag,
    ft.troponin_t_ngml,
    CASE 
      WHEN ft.troponin_t_ngml <= 0.01 THEN 'Normal/Minimal'
      WHEN ft.troponin_t_ngml > 0.01 AND ft.troponin_t_ngml <= 0.1 THEN 'Borderline'
      WHEN ft.troponin_t_ngml > 0.1 THEN 'Elevated'
    END AS troponin_category
  FROM acs_cohort ac
  INNER JOIN first_troponin ft ON ac.hadm_id = ft.hadm_id
  WHERE ft.rn = 1
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM categorized_troponin
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;