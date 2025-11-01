WITH eligible_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
    AND d.seq_num = 1
    AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime, le.labevent_id
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.label = 'Troponin T, High Sensitivity'
    AND le.valuenum IS NOT NULL
),
initial_troponin AS (
  SELECT 
    hadm_id,
    valuenum
  FROM first_troponin
  WHERE rn = 1
),
categorized AS (
  SELECT 
    ea.hadm_id,
    CASE 
      WHEN it.valuenum < 14 THEN 'normal'
      WHEN it.valuenum < 60 THEN 'borderline'  -- 14 <= valuenum < 60
      ELSE 'myocardial injury'
    END AS category
  FROM eligible_admissions ea
  INNER JOIN initial_troponin it
    ON ea.hadm_id = it.hadm_id
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'myocardial injury' THEN 3
  END;