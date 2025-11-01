WITH ami_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, a.hadm_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 44 AND 54
  AND icd.long_title LIKE '%Acute myocardial infarction%'
),
lab_events AS (
  SELECT hadm_id, charttime, itemid, valuenum, valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE hadm_id IN (SELECT hadm_id FROM ami_patients)
  AND charttime <= (SELECT admittime + INTERVAL 3 DAY FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE hadm_id = labevents.hadm_id)
),
lab_instability AS (
  -- Simplified example; actual calculation may vary based on the definition of lab instability score
  SELECT hadm_id, COUNT(*) as lab_count, COUNTIF(valuenum IS NOT NULL AND valueuom IS NOT NULL) as valid_lab_count
  FROM lab_events
  GROUP BY hadm_id
),
percentile_lab_score AS (
  SELECT APPROX_QUANTILES(lab_count, 100)[OFFSET(75)] as percentile_75_lab_count
  FROM lab_instability
),
cohort_outcomes AS (
  SELECT 
    COUNT(DISTINCT a.hadm_id) as total_admissions,
    COUNTIF(a.dischtime IS NOT NULL AND a.deathtime IS NULL) as discharged_alive,
    COUNTIF(a.deathtime IS NOT NULL) as hospital_mortality,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR)) as avg_los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM ami_patients)
)
SELECT 
  'AMI Cohort' as cohort,
  percentile_75_lab_count,
  total_admissions,
  hospital_mortality,
  avg_los_hours
FROM percentile_lab_score, cohort_outcomes
UNION ALL
SELECT 
  'General Inpatients' as cohort,
  APPROX_QUANTILES(COUNT(*), 100)[OFFSET(75)] as percentile_75_lab_count,
  COUNT(DISTINCT hadm_id) as total_admissions,
  COUNTIF(dischtime IS NOT NULL AND deathtime IS NULL) as discharged_alive,
  COUNTIF(deathtime IS NOT NULL) as hospital_mortality,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR)) as avg_los_hours
FROM `physionet-data.mimiciv_3_1_hosp.admissions`
WHERE hadm_id NOT IN (SELECT hadm_id FROM ami_patients);