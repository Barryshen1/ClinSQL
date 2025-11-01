WITH 
  -- Identify first admissions
  first_admissions AS (
    SELECT subject_id, hadm_id, admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  
  -- Filter first admissions and relevant demographics
  eligible_patients AS (
    SELECT a.subject_id, a.hadm_id, p.anchor_age, p.gender
    FROM first_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
    WHERE a.rn = 1 AND p.gender = 'M' AND p.anchor_age BETWEEN 37 AND 47
  ),
  
  -- Identify DAPT prescriptions during hospital stay
  dapt_prescriptions AS (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug LIKE '%aspirin%' OR drug LIKE '%clopidogrel%' OR drug LIKE '%prasugrel%' OR drug LIKE '%ticagrelor%'
  ),
  
  -- Identify in-hospital mortality
  in_hospital_mortality AS (
    SELECT subject_id, hadm_id, hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  )

SELECT 
  STDDEV(mortality) AS std_dev_mortality
FROM (
  SELECT 
    COALESCE(i.hospital_expire_flag, 0) AS mortality
  FROM eligible_patients e
  LEFT JOIN dapt_prescriptions d
  ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
  LEFT JOIN in_hospital_mortality i
  ON e.subject_id = i.subject_id AND e.hadm_id = i.hadm_id
  WHERE d.hadm_id IS NOT NULL  -- Ensure patient received DAPT
);