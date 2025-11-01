WITH cohort AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_approx
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 87 AND 97
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = 10 AND (
            d.icd_code LIKE 'I20.0%' OR 
            d.icd_code LIKE 'I21.%' OR 
            d.icd_code LIKE 'I22.%'
          ))
          OR
          (d.icd_version = 9 AND (
            d.icd_code LIKE '410.%' OR 
            d.icd_code LIKE '411.1%'
          ))
        )
    )
),
first_trop AS (
  SELECT 
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c 
    ON l.hadm_id = c.hadm_id
  WHERE l.itemid = 50984
    AND l.valuenum IS NOT NULL
)
SELECT 
  CASE 
    WHEN ft.valuenum <= 0.01 THEN 'Normal/Minimal'
    WHEN ft.valuenum > 0.01 AND ft.valuenum <= 0.1 THEN 'Borderline'
    ELSE 'Elevated'
  END AS trop_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
  SUM(c.hospital_expire_flag) AS deaths,
  ROUND(SUM(c.hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent
FROM first_trop ft
INNER JOIN cohort c 
  ON ft.hadm_id = c.hadm_id
WHERE ft.rn = 1
GROUP BY trop_category
ORDER BY 
  CASE trop_category 
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;