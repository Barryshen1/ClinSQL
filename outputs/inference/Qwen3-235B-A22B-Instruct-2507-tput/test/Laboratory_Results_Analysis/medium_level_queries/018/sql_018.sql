WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),
acs_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code = 'I21'
     OR d.icd_code = 'I22'
     OR d.icd_code = 'I200'
     OR d.icd_code LIKE 'I21%'
     OR d.icd_code LIKE 'I22%'
),
troponin_t_lab AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) = 'troponin t'
),
index_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN troponin_t_lab t ON le.itemid = t.itemid
  WHERE le.valuenum IS NOT NULL
),
first_troponin_per_admission AS (
  SELECT hadm_id, valuenum
  FROM index_troponin
  WHERE rn = 1
),
admissions_with_troponin AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    ft.valuenum AS troponin_t
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  JOIN acs_admissions acs ON a.hadm_id = acs.hadm_id
  JOIN first_troponin_per_admission ft ON a.hadm_id = ft.hadm_id
),
troponin_categories AS (
  SELECT 
    hadm_id,
    troponin_t,
    los_days,
    CASE
      WHEN troponin_t <= 0.014 THEN 'normal'
      WHEN troponin_t <= 0.050 THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM admissions_with_troponin
)
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM troponin_categories
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;