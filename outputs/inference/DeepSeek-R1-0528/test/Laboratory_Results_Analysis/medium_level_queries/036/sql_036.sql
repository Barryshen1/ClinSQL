WITH ami_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      ON a.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 77 AND 87
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
      OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
    )
),
first_troponin AS (
  SELECT
    aa.hadm_id,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY aa.hadm_id ORDER BY le.charttime) AS rn
  FROM
    ami_admissions aa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON aa.hadm_id = le.hadm_id
  WHERE
    le.itemid = 51006  -- hs-TnT itemid
),
categorized AS (
  SELECT
    hadm_id,
    CASE
      WHEN troponin_value < 14 THEN 'normal'
      WHEN troponin_value BETWEEN 14 AND 52 THEN 'borderline'
      WHEN troponin_value > 52 THEN 'myocardial injury'
    END AS category
  FROM
    first_troponin
  WHERE
    rn = 1
    AND troponin_value IS NOT NULL  -- Exclude non-numeric results
)
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized), 2) AS percentage
FROM
  categorized
GROUP BY
  category
ORDER BY
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'myocardial injury' THEN 3
  END;