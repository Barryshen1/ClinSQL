WITH acs_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '410%') 
          OR (di.icd_version = 9 AND di.icd_code LIKE '411%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I22%')
          OR (di.icd_version = 10 AND di.icd_code = 'I20.0')
        )
    )
),
filtered_admissions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime
  FROM acs_admissions
  WHERE age_at_admission BETWEEN 80 AND 90
),
first_troponin AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.valuenum AS troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 51006
    AND l.hadm_id IN (SELECT hadm_id FROM filtered_admissions)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),
categorized AS (
  SELECT 
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    ft.troponin_value,
    CASE 
      WHEN ft.troponin_value <= 14 THEN 'Normal'
      WHEN ft.troponin_value > 14 AND ft.troponin_value <= 50 THEN 'Borderline'
      WHEN ft.troponin_value > 50 THEN 'Myocardial Injury'
    END AS category
  FROM filtered_admissions fa
  INNER JOIN first_troponin ft
    ON fa.hadm_id = ft.hadm_id
)
SELECT 
  category,
  COUNT(*) AS count_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(DATETIME_DIFF(dischtime, admittime, DAY)), 2) AS mean_los_days
FROM categorized
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;