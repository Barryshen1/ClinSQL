WITH acs_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 79 AND 89
    AND d.seq_num = 1
    AND (
      d.icd_code = 'I200' OR 
      d.icd_code LIKE 'I21%' OR 
      d.icd_code = 'I240'
    )
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN acs_admissions a
    ON l.hadm_id = a.hadm_id
  WHERE 
    l.itemid = 50341
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM (
  SELECT 
    hadm_id,
    CASE 
      WHEN valuenum <= 0.014 THEN 'Normal'
      WHEN valuenum > 0.014 AND valuenum <= 0.09 THEN 'Borderline'
      WHEN valuenum > 0.09 THEN 'Elevated'
    END AS troponin_category
  FROM first_troponin
  WHERE rn = 1
) categorized
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;