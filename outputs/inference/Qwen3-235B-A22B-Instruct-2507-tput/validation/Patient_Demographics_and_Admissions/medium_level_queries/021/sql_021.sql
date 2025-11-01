WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    s.curr_service,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.services s
    ON a.hadm_id = s.hadm_id
),
surgical_patients AS (
  SELECT *
  FROM patient_admissions
  WHERE gender = 'M'
    AND age_at_admit >= 67 AND age_at_admit <= 77
    AND curr_service IN ('SURGERY', 'CARDIAC SURGERY', 'NEUROSURGERY', 'ENT', 'ORTHO', 'UROLOGY', 'PLASTIC SURG', 'VASCULAR SURG', 'TRANSPLANT')
),
cohort_outcomes AS (
  SELECT
    hadm_id,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      WHEN discharge_location = 'HOME' THEN 'Discharged Home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'HOME HEALTH CARE', 'LTACH', 'PSYCH', 'NF', 'ICF', 'SKILLED NURSING FACILITY') THEN 'Discharged to Facility'
      ELSE NULL
    END AS outcome_group,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM surgical_patients
  WHERE dischtime IS NOT NULL AND admittime IS NOT NULL AND dischtime >= admittime
),
summary_stats AS (
  SELECT
    outcome_group,
    AVG(los_days) AS mean_los,
    STDDEV(los_days) AS sd_los,
    AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0.0 END) AS pct_los_le_7_days
  FROM cohort_outcomes
  WHERE outcome_group IS NOT NULL
  GROUP BY outcome_group
)
SELECT
  outcome_group,
  ROUND(mean_los, 2) AS mean_los_days,
  ROUND(sd_los, 2) AS sd_los_days,
  ROUND(pct_los_le_7_days * 100, 1) AS pct_los_le_7_days
FROM summary_stats
ORDER BY outcome_group;