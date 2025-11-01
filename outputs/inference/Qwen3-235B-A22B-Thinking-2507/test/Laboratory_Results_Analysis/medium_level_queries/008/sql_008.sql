WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 87 AND 97
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (d.icd_code = 'I200' OR d.icd_code LIKE 'I21%')
    )
),
troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE d.label = 'Troponin T'
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
    c.hospital_expire_flag,
    t.valuenum,
    CASE 
      WHEN t.valuenum < 14 THEN 'Normal/Minimal'
      WHEN t.valuenum < 30 THEN 'Borderline'
      ELSE 'Elevated'
    END AS category
  FROM cohort c
  INNER JOIN first_troponin t
    ON c.hadm_id = t.hadm_id
)
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(hospital_expire_flag), 4) AS mortality_rate
FROM combined
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;