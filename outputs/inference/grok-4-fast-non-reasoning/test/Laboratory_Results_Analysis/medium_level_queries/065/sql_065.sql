WITH ami_cohort AS (
  -- Identify patients: males 49-59 with AMI admission
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.icd_code LIKE '410%'  -- ICD-9 for AMI; extend to 'I21%' if including ICD-10
),
first_troponin_times AS (
  -- For each qualifying admission, find the earliest charttime with troponin T >0.04
  SELECT ac.hadm_id, MIN(le.charttime) AS first_troponin_time
  FROM ami_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ac.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE li.label LIKE '%troponin t%'
    AND le.valuenum > 0.04
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
  GROUP BY ac.hadm_id
),
initial_troponins AS (
  -- Get the valuenum at the first qualifying charttime per hadm_id
  SELECT ftt.hadm_id, le.valuenum AS initial_troponin
  FROM first_troponin_times ftt
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ftt.hadm_id = le.hadm_id
    AND ftt.first_troponin_time = le.charttime
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE li.label LIKE '%troponin t%'
    AND le.valuenum > 0.04
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
)
-- Compute median and IQR across all initial values
SELECT
  PERCENTILE_CONT(initial_troponin, 0.5) AS median_troponin,
  PERCENTILE_CONT(initial_troponin, 0.75) - PERCENTILE_CONT(initial_troponin, 0.25) AS iqr_troponin,
  COUNT(*) AS num_patients
FROM initial_troponins;