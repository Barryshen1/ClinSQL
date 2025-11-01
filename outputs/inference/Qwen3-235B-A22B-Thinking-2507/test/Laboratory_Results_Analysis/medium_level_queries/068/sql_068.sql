WITH first_troponin AS (
  SELECT
    le.subject_id,
    le.valuenum,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM le.charttime) AS lab_year
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON le.subject_id = p.subject_id
  WHERE 
    le.itemid = 50341  -- hs-Troponin T
    AND p.gender = 'F'
    AND le.valuenum IS NOT NULL
    AND le.charttime IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY le.subject_id 
    ORDER BY le.charttime
  ) = 1
),
age_filtered AS (
  SELECT
    subject_id,
    valuenum,
    -- Calculate age at time of lab: anchor_age + (lab_year - anchor_year)
    anchor_age + (lab_year - anchor_year) AS age_at_test
  FROM first_troponin
  WHERE 
    anchor_age + (lab_year - anchor_year) BETWEEN 42 AND 52
)
SELECT
  CASE
    WHEN valuenum < 0.014 THEN 'Normal'
    WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN 'Borderline'
    WHEN valuenum >= 0.04 THEN 'Myocardial Injury'
  END AS troponin_category,
  COUNT(*) AS patient_count
FROM age_filtered
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;