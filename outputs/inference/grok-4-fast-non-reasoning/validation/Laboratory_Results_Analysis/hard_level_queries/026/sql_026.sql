WITH cohort_patients AS (
  -- Define hepatic failure cohort: males 75-85 with hepatic failure dx (any seq_num)
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND icd.icd_version = 'ICD-10'
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND d.icd_version = 'ICD-10'
    AND (d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K72%' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74%' OR d.icd_code LIKE 'K75%' OR d.icd_code LIKE 'K76%')
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND a.dischtime > a.admittime
),

general_patients AS (
  -- General comparator: all male inpatients 75-85
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND a.dischtime > a.admittime
),

-- Link to ICU stays for SOFA components (only if ICU admission exists)
cohort_with_icu AS (
  SELECT cp.*, COALESCE(i.stay_id, -1) AS stay_id
  FROM cohort_patients cp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON cp.subject_id = i.subject_id AND cp.hadm_id = i.hadm_id
),

general_with_icu AS (
  SELECT gp.*, COALESCE(i.stay_id, -1) AS stay_id
  FROM general_patients gp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON gp.subject_id = i.subject_id AND gp.hadm_id = i.hadm_id
),

-- Approximate max SOFA score in first 48h (components maxed per admission)
sofa_cohort AS (
  SELECT 
    c.hadm_id,
    -- Liver: Bilirubin (mg/dL)
    MAX(CASE WHEN le.itemid IN (50868, 1515) AND le.valuenum >= 12 THEN 4 
             WHEN le.itemid IN (50868, 1515) AND le.valuenum >= 6 THEN 3 
             WHEN le.itemid IN (50868, 1515) AND le.valuenum >= 2 THEN 2 
             WHEN le.itemid IN (50868, 1515) AND le.valuenum >= 1.2 THEN 1 ELSE 0 END) AS liver_score,
    -- Coagulation: Platelets (x10^3/uL) or INR (>5=4, >3=3, >2=2, >1.2=1)
    GREATEST(
      MAX(CASE WHEN le.itemid IN (51265, 51279) AND le.valuenum < 20 THEN 4 
               WHEN le.itemid IN (51265, 51279) AND le.valuenum < 50 THEN 3 
               WHEN le.itemid IN (51265, 51279) AND le.valuenum < 100 THEN 2 
               WHEN le.itemid IN (51265, 51279) AND le.valuenum < 150 THEN 1 ELSE 0 END),
      MAX(CASE WHEN le.itemid = 51237 AND le.valuenum > 5 THEN 4 
               WHEN le.itemid = 51237 AND le.valuenum > 3 THEN 3 
               WHEN le.itemid = 51237 AND le.valuenum > 2 THEN 2 
               WHEN le.itemid = 51237 AND le.valuenum > 1.2 THEN 1 ELSE 0 END)
    ) AS coag_score,
    -- Renal: Creatinine (mg/dL; ignore RRT for simplicity)
    MAX(CASE WHEN le.itemid IN (50912, 50976) AND le.valuenum >= 5 THEN 4 
             WHEN le.itemid IN (50912, 50976) AND le.valuenum >= 3.5 THEN 3 
             WHEN le.itemid IN (50912, 50976) AND le.valuenum >= 2 THEN 2 
             WHEN le.itemid IN (50912, 50976) AND le.valuenum >= 1.2 THEN 1 ELSE 0 END) AS renal_score,
    -- CNS: GCS (max of 15 - min GCS in 48h)
    MAX(15 - COALESCE(MIN(CASE WHEN ce.itemid IN (198, 220, 454, 456, 228) THEN ce.valuenum END), 15)) AS cns_score,
    -- Resp: Simplified (ventilated =4; PaO2/FiO2 needs more data)
    MAX(CASE WHEN pe.itemid IN (225477, 225651, 227144, 225468) THEN 4 ELSE 0 END) AS resp_score,
    -- Cardio: MAP <70 or pressors
    MAX(CASE WHEN ce.itemid IN (220045, 220179) AND ce.valuenum < 70 THEN 4  -- Low MAP
             WHEN ie.itemid IN (220615, 221906, 228532) AND ie.amount > 0 THEN 4  -- Pressors (e.g., norepi)
             ELSE 0 END) AS cardio_score
  FROM cohort_with_icu c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
    AND le.itemid IN (50868, 1515, 51265, 51279, 51237, 50912, 50976)
    AND le.charttime >= c.admittime AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.subject_id = ce.subject_id AND c.hadm_id = ce.hadm_id AND c.stay_id = ce.stay_id
    AND ce.itemid IN (220045, 220179, 198, 220, 454, 456, 228)
    AND ce.charttime >= c.admittime AND ce.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON c.subject_id = pe.subject_id AND c.hadm_id = pe.hadm_id AND c.stay_id = pe.stay_id
    AND pe.itemid IN (225477, 225651, 227144, 225468)
    AND pe.starttime >= c.admittime AND pe.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
    ON c.subject_id = ie.subject_id AND c.hadm_id = ie.hadm_id AND c.stay_id = ie.stay_id
    AND ie.itemid IN (220615, 221906, 228532)
    AND ie.starttime >= c.admittime AND ie.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  WHERE c.stay_id != -1 OR (c.stay_id = -1 AND 1=0)  -- Only ICU for SOFA; non-ICU get 0 implicitly via LEFT JOIN
  GROUP BY c.hadm_id
),

sofa_general AS (
  -- Repeat SOFA logic for general patients (similar structure)
  SELECT 
    g.hadm_id,
    MAX(CASE WHEN le.itemid IN (50868, 1515) AND le.valuenum >= 12 THEN 4 
             WHEN le.itemid IN (50868, 1515) AND le.valuenum >= 6 THEN 3 
             WHEN le.itemid IN (50868, 1515) AND le.valuenum >= 2 THEN 2 
             WHEN le.itemid IN (50868, 1515) AND le.valuenum >= 1.2 THEN 1 ELSE 0 END) AS liver_score,
    GREATEST(
      MAX(CASE WHEN le.itemid IN (51265, 51279) AND le.valuenum < 20 THEN 4 
               WHEN le.itemid IN (51265, 51279) AND le.valuenum < 50 THEN 3 
               WHEN le.itemid IN (51265, 51279) AND le.valuenum < 100 THEN 2 
               WHEN le.itemid IN (51265, 51279) AND le.valuenum < 150 THEN 1 ELSE 0 END),
      MAX(CASE WHEN le.itemid = 51237 AND le.valuenum > 5 THEN 4 
               WHEN le.itemid = 51237 AND le.valuenum > 3 THEN 3 
               WHEN le.itemid = 51237 AND le.valuenum > 2 THEN 2 
               WHEN le.itemid = 51237 AND le.valuenum > 1.2 THEN 1 ELSE 0 END)
    ) AS coag_score,
    MAX(CASE WHEN le.itemid IN (50912, 50976) AND le.valuenum >= 5 THEN 4 
             WHEN le.itemid IN (50912, 50976) AND le.valuenum >= 3.5 THEN 3 
             WHEN le.itemid IN (50912, 50976) AND le.valuenum >= 2 THEN 2 
             WHEN le.itemid IN (50912, 50976) AND le.valuenum >= 1.2 THEN 1 ELSE 0 END) AS renal_score,
    MAX(15 - COALESCE(MIN(CASE WHEN ce.itemid IN (198, 220, 454, 456, 228) THEN ce.valuenum END), 15)) AS cns_score,
    MAX(CASE WHEN pe.itemid IN (225477, 225651, 227144, 225468) THEN 4 ELSE 0 END) AS resp_score,
    MAX(CASE WHEN ce.itemid IN (220045, 220179) AND ce.valuenum < 70 THEN 4
             WHEN ie.itemid IN (220615, 221906, 228532) AND ie.amount > 0 THEN 4
             ELSE 0 END) AS cardio_score
  FROM general_with_icu g
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON g.subject_id = le.subject_id AND g.hadm_id = le.hadm_id
    AND le.itemid IN (50868, 1515, 51265, 51279, 51237, 50912, 50976)
    AND le.charttime >= g.admittime AND le.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON g.subject_id = ce.subject_id AND g.hadm_id = ce.hadm_id AND g.stay_id = ce.stay_id
    AND ce.itemid IN (220045, 220179, 198, 220, 454, 456, 228)
    AND ce.charttime >= g.admittime AND ce.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON g.subject_id = pe.subject_id AND g.hadm_id = pe.hadm_id AND g.stay_id = pe.stay_id
    AND pe.itemid IN (225477, 225651, 227144, 225468)
    AND pe.starttime >= g.admittime AND pe.starttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
    ON g.subject_id = ie.subject_id AND g.hadm_id = ie.hadm_id AND g.stay_id = ie.stay_id
    AND ie.itemid IN (220615, 221906, 228532)
    AND ie.starttime >= g.admittime AND ie.starttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
  WHERE g.stay_id != -1 OR (g.stay_id = -1 AND 1=0)
  GROUP BY g.hadm_id
),

-- Metrics for cohort and general
cohort_metrics AS (
  SELECT 
    'Cohort' AS group_type,
    COUNT(*) AS n_admissions,
    ROUND(AVG(COALESCE(s.liver_score + s.coag_score + s.renal_score + s.cns_score + s.resp_score + s.cardio_score, 0)), 2) AS avg_max_instability_score,
    ROUND(AVG(EXTRACT(DAY FROM (c.dischtime - c.admittime))), 2) AS avg_los_days,
    ROUND(AVG(CASE WHEN c.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS mortality_pct
  FROM cohort_patients c
  LEFT JOIN sofa_cohort s ON c.hadm_id = s.hadm_id
),

general_metrics AS (
  SELECT 
    'General' AS group_type,
    COUNT(*) AS n_admissions,
    ROUND(AVG(COALESCE(s.liver_score + s.coag_score + s.renal_score + s.cns_score + s.resp_score + s.cardio_score, 0)), 2) AS avg_max_instability_score,
    ROUND(AVG(EXTRACT(DAY FROM (g.dischtime - g.admittime))), 2) AS avg_los_days,
    ROUND(AVG(CASE WHEN g.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS mortality_pct
  FROM general_patients g
  LEFT JOIN sofa_general s ON g.hadm_id = s.hadm_id
),

-- Critical labs: % admissions with abnormal in first 48h (using EXISTS for efficiency)
lab_frequencies AS (
  SELECT 
    lab_name,
    ROUND(
      (COUNT(DISTINCT CASE WHEN cohort_has_abnormal = 1 THEN c.hadm_id END) * 100.0 / COUNT(DISTINCT c.hadm_id)), 2
    ) AS cohort_freq_pct,
    ROUND(
      (COUNT(DISTINCT CASE WHEN general_has_abnormal = 1 THEN g.hadm_id END) * 100.0 / COUNT(DISTINCT g.hadm_id)), 2
    ) AS general_freq_pct
  FROM (
    SELECT 'Bilirubin >6 mg/dL' AS lab_name, c.hadm_id,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = c.subject_id AND le.hadm_id = c.hadm_id
               AND le.itemid IN (50868, 1515) AND le.valuenum > 6 AND le.valueuom = 'mg/dL'
               AND le.charttime >= c.admittime AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END AS cohort_has_abnormal,
           NULL AS general_has_abnormal
    FROM cohort_patients c
    UNION ALL
    SELECT 'ALT >1000 U/L', NULL, NULL, 
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = g.subject_id AND le.hadm_id = g.hadm_id
               AND le.itemid = 5089 AND le.valuenum > 1000 AND le.valueuom = 'U/L'
               AND le.charttime >= g.admittime AND le.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END
    FROM general_patients g
    UNION ALL
    SELECT 'AST >1000 U/L', c.hadm_id,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = c.subject_id AND le.hadm_id = c.hadm_id
               AND le.itemid = 5090 AND le.valuenum > 1000 AND le.valueuom = 'U/L'
               AND le.charttime >= c.admittime AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END, NULL
    FROM cohort_patients c
    UNION ALL
    SELECT 'AST >1000 U/L', NULL, NULL,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = g.subject_id AND le.hadm_id = g.hadm_id
               AND le.itemid = 5090 AND le.valuenum > 1000 AND le.valueuom = 'U/L'
               AND le.charttime >= g.admittime AND le.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END
    FROM general_patients g
    UNION ALL
    SELECT 'INR >2', c.hadm_id,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = c.subject_id AND le.hadm_id = c.hadm_id
               AND le.itemid = 51237 AND le.valuenum > 2
               AND le.charttime >= c.admittime AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END, NULL
    FROM cohort_patients c
    UNION ALL
    SELECT 'INR >2', NULL, NULL,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = g.subject_id AND le.hadm_id = g.hadm_id
               AND le.itemid = 51237 AND le.valuenum > 2
               AND le.charttime >= g.admittime AND le.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END
    FROM general_patients g
    UNION ALL
    SELECT 'Albumin <2.5 g/dL', c.hadm_id,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = c.subject_id AND le.hadm_id = c.hadm_id
               AND le.itemid = 50862 AND le.valuenum < 2.5 AND le.valueuom = 'g/dL'
               AND le.charttime >= c.admittime AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END, NULL
    FROM cohort_patients c
    UNION ALL
    SELECT 'Albumin <2.5 g/dL', NULL, NULL,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = g.subject_id AND le.hadm_id = g.hadm_id
               AND le.itemid = 50862 AND le.valuenum < 2.5 AND le.valueuom = 'g/dL'
               AND le.charttime >= g.admittime AND le.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END
    FROM general_patients g
    UNION ALL
    SELECT 'Creatinine >2 mg/dL', c.hadm_id,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = c.subject_id AND le.hadm_id = c.hadm_id
               AND le.itemid IN (50912, 50976) AND le.valuenum > 2 AND le.valueuom = 'mg/dL'
               AND le.charttime >= c.admittime AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END, NULL
    FROM cohort_patients c
    UNION ALL
    SELECT 'Creatinine >2 mg/dL', NULL, NULL,
           CASE WHEN EXISTS (
             SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
             WHERE le.subject_id = g.subject_id AND le.hadm_id = g.hadm_id
               AND le.itemid IN (50912, 50976) AND le.valuenum > 2 AND le.valueuom = 'mg/dL'
               AND le.charttime >= g.admittime AND le.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
           ) THEN 1 ELSE 0 END
    FROM general_patients g
  ) labs
  LEFT JOIN cohort_patients c ON labs.hadm_id = c.hadm_id AND labs.cohort_has_abnormal = 1
  LEFT JOIN general_patients g ON labs.hadm_id = g.hadm_id AND labs.general_has_abnormal = 1
  GROUP BY lab_name
)

-- Unified output: Metrics first, then labs (columns repurposed: n_adm, instability, los, mortality -> for labs: cohort%, general%)
SELECT group_type, n_admissions, avg_max_instability_score, avg_los_days, mortality_pct
FROM cohort_metrics
UNION ALL
SELECT group_type, n_admissions, avg_max_instability_score, avg_los_days, mortality_pct
FROM general_metrics
UNION ALL
SELECT lab_name AS group_type, NULL AS n_admissions, NULL AS avg_max_instability_score, 
       cohort_freq_pct AS avg_los_days, general_freq_pct AS mortality_pct  -- Repurposed for lab frequencies
FROM lab_frequencies
ORDER BY group_type;