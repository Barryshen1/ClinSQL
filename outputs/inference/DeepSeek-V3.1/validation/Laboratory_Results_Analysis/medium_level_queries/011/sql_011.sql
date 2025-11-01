WITH chest_pain_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    AND di.seq_num = 1
    AND di.icd_code LIKE 'R07%'  -- Chest pain codes (R07.0 to R07.9)
),
first_troponin AS (
  SELECT 
    cpa.hadm_id,
    MIN(le.charttime) AS first_charttime
  FROM chest_pain_admissions cpa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cpa.hadm_id = le.hadm_id
  WHERE le.itemid = 51004  -- Troponin T (High Sensitivity)
    AND le.valuenum IS NOT NULL
  GROUP BY cpa.hadm_id
),
troponin_values AS (
  SELECT 
    cpa.hadm_id,
    le.valuenum AS troponin_value,
    CASE 
      WHEN le.valuenum < 14 THEN 'Normal'
      WHEN le.valuenum BETWEEN 14 AND 19 THEN 'Borderline'
      WHEN le.valuenum >= 20 THEN 'Myocardial injury'
    END AS category
  FROM chest_pain_admissions cpa
  INNER JOIN first_troponin ft
    ON cpa.hadm_id = ft.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ft.hadm_id = le.hadm_id
      AND ft.first_charttime = le.charttime
      AND le.itemid = 51004
),
category_counts AS (
  SELECT 
    category,
    COUNT(*) AS count
  FROM troponin_values
  GROUP BY category
),
total_count AS (
  SELECT COUNT(*) AS total
  FROM troponin_values
)
SELECT 
  category,
  count,
  ROUND(count * 100.0 / total, 2) AS percentage
FROM category_counts, total_count
ORDER BY category;