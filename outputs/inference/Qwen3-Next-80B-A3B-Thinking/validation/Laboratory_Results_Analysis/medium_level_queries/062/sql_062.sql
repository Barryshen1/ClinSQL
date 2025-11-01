WITH acs_cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code IN ('4111', '4118')))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I20.0%' OR d.icd_code LIKE 'I21.%'))
    )
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50911
    AND l.hadm_id IN (SELECT hadm_id FROM acs_cohort)
),
troponin_categories AS (
  SELECT 
    ft.hadm_id,
    ft.valuenum,
    CASE
      WHEN ft.valuenum <= 14 THEN 'Normal'
      WHEN ft.valuenum > 14 AND ft.valuenum < 40 THEN 'Borderline'
      WHEN ft.valuenum >= 40 THEN 'Myocardial Injury'
      ELSE NULL
    END AS troponin_category
  FROM first_troponin ft
  WHERE ft.rn = 1
)
SELECT 
  tc.troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los
FROM troponin_categories tc
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON tc.hadm_id = a.hadm_id
WHERE tc.troponin_category IS NOT NULL
GROUP BY tc.troponin_category;