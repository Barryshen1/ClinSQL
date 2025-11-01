WITH chest_pain_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%chest pain%'
    AND d_diag.icd_version = 10
),
patient_age_gender AS (
  SELECT p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS adm_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN chest_pain_admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
),
troponin_t_labs AS (
  SELECT l.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT t.hadm_id, t.valuenum
  FROM troponin_t_labs t
  WHERE t.rn = 1
),
troponin_category AS (
  SELECT 
    ft.hadm_id,
    ft.valuenum,
    CASE
      WHEN ft.valuenum <= 0.014 THEN 'Normal'
      WHEN ft.valuenum < 0.030 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM first_troponin ft
),
cohort AS (
  SELECT 
    tc.troponin_category,
    a.hospital_expire_flag,
    1 AS count_val
  FROM troponin_category tc
  JOIN chest_pain_admissions a ON tc.hadm_id = a.hadm_id
  JOIN patient_age_gender pag ON a.subject_id = pag.subject_id
)
SELECT
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  SUM(hospital_expire_flag) AS in_hospital_mortality_count,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_rate_percent
FROM cohort
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;