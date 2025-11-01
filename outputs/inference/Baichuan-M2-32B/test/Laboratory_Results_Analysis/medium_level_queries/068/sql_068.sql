WITH troponin_labs AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    le.labevent_id,
    p.anchor_year,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON le.subject_id = p.subject_id
  WHERE dli.label = 'hs-Troponin T'
    AND le.valueuom = 'ng/mL'
    AND p.gender = 'F'
    AND le.valuenum IS NOT NULL
    AND le.valuenum >= 0  -- ensure non-negative
),
first_troponin_per_patient AS (
  SELECT 
    *,
    EXTRACT(YEAR FROM charttime) - (anchor_year - anchor_age) AS age_at_lab,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY charttime, labevent_id) AS rn
  FROM troponin_labs
)
SELECT 
  CASE 
    WHEN valuenum < 0.014 THEN 'Normal'
    WHEN valuenum >= 0.014 AND valuenum < 0.04 THEN 'Borderline'
    WHEN valuenum >= 0.04 THEN 'Myocardial Injury'
    ELSE 'Unknown'
  END AS category,
  COUNT(DISTINCT subject_id) AS patient_count
FROM first_troponin_per_patient
WHERE rn = 1
  AND age_at_lab BETWEEN 42 AND 52
GROUP BY category
ORDER BY category;