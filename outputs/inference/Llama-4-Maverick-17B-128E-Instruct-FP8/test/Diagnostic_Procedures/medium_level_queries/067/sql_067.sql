WITH 
-- Step 1: Filter patients
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 39 AND 49
),

-- Step 2: Identify admissions with ACS
acs_admissions AS (
  SELECT a.hadm_id, 
         CASE 
           WHEN MIN(d.seq_num) = 1 THEN 'Primary'
           ELSE 'Secondary'
         END AS acs_priority
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE a.subject_id IN (SELECT subject_id FROM filtered_patients)
    AND dicd.long_title LIKE '%Acute Coronary Syndrome%'  -- Simplified ACS identification
  GROUP BY a.hadm_id
),

-- Step 3: Calculate LOS and count ICU stays
admission_characteristics AS (
  SELECT aa.hadm_id, 
         aa.acs_priority,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         COUNT(ic.stay_id) AS num_icu_stays
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN acs_admissions aa ON a.hadm_id = aa.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  GROUP BY aa.hadm_id, aa.acs_priority, a.dischtime, a.admittime
),

-- Step 4: Count ultrasounds
ultrasound_counts AS (
  SELECT a.hadm_id, 
         COUNT(pe.itemid) AS num_ultrasounds
  FROM admission_characteristics a
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON a.hadm_id = pe.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%ultrasound%' OR di.label LIKE '%echo%'
  GROUP BY a.hadm_id
)

-- Step 5: Stratify and calculate statistics
SELECT 
  CASE 
    WHEN ac.num_icu_stays BETWEEN 1 AND 4 THEN '1-4 stays'
    WHEN ac.num_icu_stays BETWEEN 5 AND 7 THEN '5-7 stays'
    ELSE 'Outside range'
  END AS icu_stay_strata,
  ac.acs_priority,
  APPROX_QUANTILES(uc.num_ultrasounds, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(uc.num_ultrasounds, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(uc.num_ultrasounds, 100)[OFFSET(75)] AS p75
FROM admission_characteristics ac
JOIN ultrasound_counts uc ON ac.hadm_id = uc.hadm_id
WHERE ac.los BETWEEN 1 AND 7
GROUP BY icu_stay_strata, ac.acs_priority
ORDER BY icu_stay_strata, ac.acs_priority;