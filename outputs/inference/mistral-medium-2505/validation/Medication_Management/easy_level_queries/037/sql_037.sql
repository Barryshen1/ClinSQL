WITH ace_inhibitors AS (
  -- List of common ACE inhibitors (this should be expanded based on actual data)
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%lisinopril%'
     OR LOWER(drug) LIKE '%enalapril%'
     OR LOWER(drug) LIKE '%ramipril%'
     OR LOWER(drug) LIKE '%captopril%'
     OR LOWER(drug) LIKE '%benazepril%'
     OR LOWER(drug) LIKE '%fosinopril%'
     OR LOWER(drug) LIKE '%perindopril%'
     OR LOWER(drug) LIKE '%quinapril%'
     OR LOWER(drug) LIKE '%trandolapril%'
     OR LOWER(drug) LIKE '%moexipril%'
),

female_inpatients AS (
  -- Get 55-year-old female inpatients
  SELECT
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 55
    AND a.admission_type NOT LIKE '%EMERGENCY%'
    AND a.admission_type NOT LIKE '%OBSERVATION%'
),

prescription_durations AS (
  -- Calculate duration for each ACE inhibitor prescription
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN female_inpatients fi
    ON p.subject_id = fi.subject_id AND p.hadm_id = fi.hadm_id
  JOIN ace_inhibitors ai
    ON LOWER(p.drug) = LOWER(ai.drug)
  WHERE p.stoptime IS NOT NULL  -- Exclude ongoing prescriptions
    AND p.starttime < p.stoptime  -- Ensure valid time range
)

-- Calculate the 25th percentile duration
SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS percentile_25_duration
FROM prescription_durations
LIMIT 1;