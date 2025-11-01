WITH cohort AS (
  -- Define cohort: males aged 70-80 with hemorrhagic stroke (ICD-10 I60-I61)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%')
    AND d.seq_num <= 5  -- Top diagnoses for specificity
),

instability_scores AS (
  -- Compute instability score: count of unstable lab events in first 48h per hadm_id
  SELECT 
    c.hadm_id,
    COUNT(*) AS instability_score  -- Count events (rows) for instability volume
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id 
    AND c.hadm_id = le.hadm_id
    AND le.charttime >= c.admittime
    AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  WHERE le.valuenum IS NOT NULL
    AND le.itemid IN (
      51222,  -- WBC (Hematology)
      51265,  -- Hgb
      51279,  -- Plt
      50971,  -- Sodium (Chemistry)
      50983,  -- Potassium
      51006,  -- Creatinine
      51237,  -- INR (Coagulation)
      51516   -- pH (Blood Gases, arterial/venous proxy)
    )
    AND (le.flag = 'abnormal' 
         OR (le.valuenum < le.ref_range_lower AND le.ref_range_lower IS NOT NULL)
         OR (le.valuenum > le.ref_range_upper AND le.ref_range_upper IS NOT NULL))
  GROUP BY c.hadm_id
),

all_admissions AS (
  -- For general inpatient rate: all admissions with lab join
  SELECT 
    a.hadm_id,
    COUNT(*) AS general_instability  -- Consistent with cohort: count events
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id 
    AND a.hadm_id = le.hadm_id
    AND le.charttime >= a.admittime
    AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND le.itemid IN (51222, 51265, 51279, 50971, 50983, 51006, 51237, 51516)
    AND le.valuenum IS NOT NULL
    AND (le.flag = 'abnormal' 
         OR (le.valuenum < le.ref_range_lower AND le.ref_range_lower IS NOT NULL)
         OR (le.valuenum > le.ref_range_upper AND le.ref_range_upper IS NOT NULL))
  GROUP BY a.hadm_id
),

general_rate AS (
  SELECT AVG(CASE WHEN COALESCE(general_instability, 0) > 0 THEN 1.0 ELSE 0 END) AS general_event_rate
  FROM all_admissions
),

percentile_calc AS (
  SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(instability_score, 0)) AS p25_instability_score
  FROM instability_scores
)

-- Main aggregation: cohort metrics + general comparison
SELECT 
  pc.p25_instability_score,
  
  -- Cohort critical-lab event rate (proportion with >0 unstable labs)
  AVG(CASE WHEN COALESCE(is.instability_score, 0) > 0 THEN 1.0 ELSE 0 END) AS cohort_event_rate,
  
  -- General inpatient critical-lab event rate
  gr.general_event_rate,
  
  -- Mean LOS (days) for cohort
  AVG(DATE_DIFF(c.dischtime, c.admittime, DAY)) AS mean_los_days,
  
  -- In-hospital mortality rate (cohort)
  AVG(c.hospital_expire_flag) AS mortality_rate

FROM cohort c
LEFT JOIN instability_scores is 
  ON c.hadm_id = is.hadm_id
CROSS JOIN general_rate gr
CROSS JOIN percentile_calc pc;