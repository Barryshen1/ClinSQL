WITH chest_pain_admissions AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND diag.seq_num = 1
    AND d.icd_code LIKE 'R07%'
),
first_troponin AS (
  SELECT 
    cpa.subject_id,
    cpa.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY cpa.hadm_id ORDER BY le.charttime) AS rn
  FROM chest_pain_admissions cpa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cpa.subject_id = le.subject_id AND cpa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.itemid = 51003 -- Troponin T (High Sensitivity)
    AND le.valuenum IS NOT NULL
),
categorized_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    troponin_value,
    CASE
      WHEN troponin_value <= 14 THEN 'Normal'
      WHEN troponin_value <= 19 THEN 'Borderline'
      ELSE 'Myocardial injury'
    END AS category
  FROM first_troponin
  WHERE rn = 1
)
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage,
  ROUND(AVG(troponin_value), 1) AS mean,
  ROUND(APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)], 1) AS median,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)], 1) AS q1,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)], 1) AS q3
FROM categorized_troponin
GROUP BY category
ORDER BY category;