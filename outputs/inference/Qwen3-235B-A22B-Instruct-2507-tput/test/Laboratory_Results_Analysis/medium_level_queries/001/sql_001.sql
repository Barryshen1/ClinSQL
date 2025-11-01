WITH female_40_50 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age >= 40
    AND anchor_age <= 50
),
ami_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%myocardial infarction%'
    AND LOWER(d.long_title) LIKE '%acute%'
),
troponin_t AS (
  SELECT l.hadm_id, l.charttime, l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d
    ON l.itemid = d.itemid
  WHERE LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    hadm_id,
    MIN(charttime) AS first_troponin_time
  FROM troponin_t
  GROUP BY hadm_id
),
initial_troponin AS (
  SELECT tt.hadm_id, tt.valuenum
  FROM troponin_t tt
  JOIN first_troponin ft
    ON tt.hadm_id = ft.hadm_id AND tt.charttime = ft.first_troponin_time
),
categorized AS (
  SELECT
    CASE
      WHEN valuenum <= 0.014 THEN 'normal'
      WHEN valuenum <= 0.050 THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM initial_troponin it
  JOIN ami_admissions am ON it.hadm_id = am.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON am.hadm_id = a.hadm_id
  JOIN female_40_50 f ON a.subject_id = f.subject_id
)
SELECT category, COUNT(*) AS count
FROM categorized
GROUP BY category
ORDER BY category;