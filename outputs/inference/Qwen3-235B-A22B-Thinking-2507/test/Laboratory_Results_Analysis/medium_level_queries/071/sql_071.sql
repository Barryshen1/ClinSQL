WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND (
            d.icd_code LIKE 'I20.%' OR
            d.icd_code LIKE 'I21.%' OR
            d.icd_code LIKE 'I22.%' OR
            d.icd_code LIKE 'I23.%' OR
            d.icd_code LIKE 'I24.%' OR
            d.icd_code IN ('R07.2', 'R07.3', 'R07.4', 'R07.9')
          )) OR
          (d.icd_version = 9 AND (
            d.icd_code LIKE '410%' OR 
            d.icd_code = '4111' OR
            d.icd_code LIKE '7865%'
          ))
        )
    )
),
troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50189
    AND l.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    hadm_id,
    valuenum
  FROM troponin
  WHERE rn = 1
),
combined AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ft.valuenum,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / (24*60*60) AS los_days,
    CASE 
      WHEN ft.valuenum <= 0.01 THEN 'Normal'
      WHEN ft.valuenum > 0.01 AND ft.valuenum <= 0.03 THEN 'Borderline'
      WHEN ft.valuenum > 0.03 THEN 'Elevated'
    END AS troponin_category
  FROM cohort c
  INNER JOIN first_troponin ft
    ON c.hadm_id = ft.hadm_id
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(los_days) AS avg_los_days
FROM combined
WHERE troponin_category IS NOT NULL
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;