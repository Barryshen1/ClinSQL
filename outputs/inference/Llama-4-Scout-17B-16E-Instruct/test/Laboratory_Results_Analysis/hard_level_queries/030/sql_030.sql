WITH 
-- Identify cohort
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND d.icd_code LIKE '%Asthma%'
),

-- Lab events in first 48 hours
lab_events_48hrs AS (
  SELECT 
    le.hadm_id,
    le.itemid,
    le.charttime,
    le.value,
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE 
    le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
),

-- Calculate lab instability score (example: count of lab events)
lab_instability AS (
  SELECT 
    hadm_id,
    COUNT(*) AS lab_count
  FROM 
    lab_events_48hrs
  GROUP BY 
    hadm_id
),

-- Final results
final_results AS (
  SELECT 
    ci.hadm_id,
    ci.admittime,
    ci.anchor_age,
    ci.gender,
    li.lab_count,
    APPROX_QUANTILES(li.lab_count, 1)[OFFSET(1)] AS percentile_75_lab_count,
    (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.admissions`) AS all_inpatients,
    COALESCE((SELECT AVG(los) FROM `physionet-data.mimiciv_3_1_icu.icustays`), 0) AS avg_icu_los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'Yes'
      ELSE 'No'
    END AS in_hospital_mortality
  FROM 
    cohort ci
    JOIN lab_instability li ON ci.hadm_id = li.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ci.hadm_id = a.hadm_id
)

SELECT * FROM final_results;