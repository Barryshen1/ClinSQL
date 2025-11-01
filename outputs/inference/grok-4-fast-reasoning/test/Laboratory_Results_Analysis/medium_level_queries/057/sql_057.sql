WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code = 'I200'))
    )
),
first_trop AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c
    ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 50586
    AND le.valuenum IS NOT NULL
)
SELECT 
  CASE 
    WHEN valuenum <= 0.04 THEN 'normal'
    WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'borderline'
    ELSE 'elevated'
  END AS category,
  COUNT(DISTINCT hadm_id) AS admission_count
FROM first_trop
WHERE rn = 1
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;