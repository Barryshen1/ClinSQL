WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      (dd.icd_code LIKE '410%' AND di.icd_version = 9) OR
      (dd.icd_code LIKE 'I21%' AND di.icd_version = 10) OR
      (dd.icd_code LIKE 'I22%' AND di.icd_version = 10)
    )
    AND di.seq_num = 1  -- primary diagnosis
),
first_troponin AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    l.valuenum AS troponin_value,
    CASE 
      WHEN l.valuenum <= 0.04 THEN 'Normal'
      WHEN l.valuenum > 0.04 AND l.valuenum < 0.40 THEN 'Borderline'
      WHEN l.valuenum >= 0.40 THEN 'Elevated'
    END AS category
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON l.itemid = dli.itemid
  WHERE dli.label = 'Troponin I'
    AND l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY l.charttime) = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM first_troponin), 2) AS percentage,
  ROUND(AVG(troponin_value), 2) AS mean,
  ROUND(APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)], 2) AS median,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)], 2) AS q1,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)], 2) AS q3
FROM first_troponin
GROUP BY category
ORDER BY category;