WITH age_filtered AS (
  SELECT 
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
),
dapt_prescriptions AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.stoptime,
    CASE 
      WHEN LOWER(p.drug) IN ('aspirin', 'acetylsalicylic acid') THEN 'aspirin'
      WHEN LOWER(p.drug) IN ('clopidogrel', 'plavix', 'prasugrel', 'efient', 'ticagrelor', 'brilinta') THEN 'p2y12'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN age_filtered a
    ON p.hadm_id = a.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND LOWER(p.drug) IN (
      'aspirin', 'acetylsalicylic acid', 
      'clopidogrel', 'plavix', 
      'prasugrel', 'efient', 
      'ticagrelor', 'brilinta'
    )
),
dapt_admissions AS (
  SELECT 
    hadm_id,
    MIN(starttime) AS dapt_start,
    MAX(stoptime) AS dapt_end,
    TIMESTAMP_DIFF(MAX(stoptime), MIN(starttime), SECOND) / (24*60*60) AS duration_days
  FROM dapt_prescriptions
  GROUP BY hadm_id
  HAVING 
    COUNTIF(drug_class = 'aspirin') >= 1 
    AND COUNTIF(drug_class = 'p2y12') >= 1
)
SELECT 
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS iqr
FROM dapt_admissions;