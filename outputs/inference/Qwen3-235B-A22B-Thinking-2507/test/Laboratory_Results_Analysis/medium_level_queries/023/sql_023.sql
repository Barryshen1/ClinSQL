WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    COALESCE(a.edregtime, a.admittime) AS start_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND d.icd_version = 10
        AND d.icd_code IN ('I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4')
    )
),
first_troponin AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    le.valuenum AS troponin_t,
    ROW_NUMBER() OVER (
      PARTITION BY c.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  WHERE 
    le.itemid = 50191  -- Troponin T
    AND le.charttime >= c.start_time
    AND le.valuenum IS NOT NULL
),
categorized AS (
  SELECT 
    hadm_id,
    hospital_expire_flag,
    CASE 
      WHEN troponin_t <= 0.04 THEN 'normal'
      WHEN troponin_t > 0.04 AND troponin_t <= 0.1 THEN 'borderline'
      WHEN troponin_t > 0.1 THEN 'elevated'
    END AS category
  FROM first_troponin
  WHERE rn = 1
)
SELECT 
  category,
  COUNT(*) AS count_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_admissions,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate
FROM categorized
WHERE category IS NOT NULL
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'normal' THEN 1 
    WHEN 'borderline' THEN 2 
    WHEN 'elevated' THEN 3 
  END;