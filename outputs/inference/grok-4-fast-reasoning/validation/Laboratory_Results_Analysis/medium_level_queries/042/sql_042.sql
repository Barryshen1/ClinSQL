WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (d.icd_code LIKE 'R07%' OR d.icd_code LIKE '786.5%')
    )
),
troponin_events AS (
  SELECT 
    c.*,
    l.charttime,
    l.valuenum,
    CASE 
      WHEN l.valuenum <= 0.01 THEN 'normal'
      WHEN l.valuenum <= 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.subject_id = l.subject_id 
    AND c.hadm_id = l.hadm_id
  WHERE l.itemid = 50922
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL 
    AND l.valuenum > 0
    AND l.charttime >= c.admittime
    AND (l.charttime <= c.dischtime OR c.dischtime IS NULL)
),
first_troponin AS (
  SELECT *
  FROM (
    SELECT *, 
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_events
  )
  WHERE rn = 1
)
SELECT 
  troponin_category,
  COUNT(*) AS count_patients,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage_of_cohort,
  SUM(hospital_expire_flag) AS num_deaths,
  ROUND(AVG(hospital_expire_flag) * 100.0, 1) AS mortality_percentage
FROM first_troponin
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category 
    WHEN 'normal' THEN 1 
    WHEN 'borderline' THEN 2 
    ELSE 3 
  END;