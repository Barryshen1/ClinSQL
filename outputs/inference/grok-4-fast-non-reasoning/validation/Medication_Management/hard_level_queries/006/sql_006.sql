WITH cohort AS (
  -- Base cohort: males aged 37-47 with postoperative ICU admission
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.admission_type,
    a.hospital_expire_flag,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type LIKE '%SURG%'  -- Postoperative surgical admission
    AND i.first_careunit IN ('SICU', 'MICU', 'CCU', 'CSICU', 'TSICU', 'NICU')  -- Ensure ICU
),

first_icu_stay AS (
  -- For each admission, take the first ICU stay to define 72h window
  SELECT *
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM cohort
  ) WHERE rn = 1
),

meds_in_window AS (
  -- Inputevents (ICU meds) in first 72h
  SELECT 
    f.subject_id,
    f.stay_id,
    f.intime,
    ie.itemid,
    di.label AS drug_name,
    TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR) AS window_end
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON ie.subject_id = f.subject_id
    AND ie.stay_id = f.stay_id
    AND ie.starttime >= f.intime
    AND ie.starttime < TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
    AND ie.amount IS NOT NULL
    AND ie.amount > 0
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
    AND di.category = 'Medications'
  WHERE di.label IS NOT NULL  -- Ensure valid drug name

  UNION ALL

  -- Prescriptions (broader orders) in first 72h
  SELECT 
    f.subject_id,
    f.stay_id,
    f.intime,
    NULL AS itemid,
    pr.drug AS drug_name,
    TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR) AS window_end
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = f.subject_id
    AND pr.hadm_id = f.hadm_id
    AND pr.starttime >= f.intime
    AND pr.starttime < TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
    AND pr.drug IS NOT NULL
),

pgc_calc AS (
  -- Compute PGC score per stay (simplified: weight by drug class, frequency=1 for unique drugs)
  SELECT 
    m.subject_id,
    m.stay_id,
    COALESCE(COUNT(DISTINCT m.drug_name), 0) AS num_unique_drugs,  -- Base count
    COALESCE(SUM(CASE 
      WHEN LOWER(m.drug_name) LIKE '%morphine%' OR LOWER(m.drug_name) LIKE '%fentanyl%' THEN 3  -- High complexity opioids
      WHEN LOWER(m.drug_name) LIKE '%vancomycin%' OR LOWER(m.drug_name) LIKE '%meropenem%' THEN 2  -- Antibiotics
      WHEN LOWER(m.drug_name) LIKE '%heparin%' OR LOWER(m.drug_name) LIKE '%insulin%' THEN 1.5  -- Anticoag/glycemic
      WHEN LOWER(m.drug_name) LIKE '%potassium%' OR LOWER(m.drug_name) LIKE '%sodium%' THEN 1  -- Electrolytes
      ELSE 1  -- Default
    END), 0) AS pgc_score  -- Sum weights; multiply by freq/complexity if detailed data available
  FROM meds_in_window m
  GROUP BY m.subject_id, m.stay_id
),

outcomes_with_readmit AS (
  -- Compute readmissions per subject (windowed count of future admissions within 30 days)
  SELECT 
    f.subject_id,
    f.stay_id,
    f.los,
    f.hospital_expire_flag,
    f.dischtime,
    f.anchor_age,
    ra.subject_id AS ra_subject_id,
    ra.admittime,
    ra.hadm_id AS ra_hadm_id,
    COUNTIF(ra.admittime > f.dischtime 
            AND ra.admittime <= TIMESTAMP_ADD(f.dischtime, INTERVAL 30 DAY)
            AND ra.hadm_id != f.hadm_id) OVER (PARTITION BY f.subject_id) > 0 AS readmit_30d_flag
  FROM first_icu_stay f
  INNER JOIN pgc_calc pg ON f.stay_id = pg.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ra
    ON ra.subject_id = f.subject_id
),

outcomes AS (
  -- Deduplicate to one row per stay (take the computed readmit flag)
  SELECT DISTINCT
    subject_id,
    stay_id,
    los,
    hospital_expire_flag,
    dischtime,
    anchor_age,
    MAX(readmit_30d_flag) AS readmit_30d  -- True if any readmit
  FROM outcomes_with_readmit
  GROUP BY subject_id, stay_id, los, hospital_expire_flag, dischtime, anchor_age
),

outcomes_with_quintiles AS (
  -- Assign quintiles to each patient
  SELECT 
    o.*,
    NTILE(5) OVER (ORDER BY o.pgc_score) AS quintile  -- Q1 low, Q5 high complexity
  FROM (
    SELECT 
      f.subject_id,
      f.stay_id,
      f.los,
      f.hospital_expire_flag,
      f.dischtime,
      f.anchor_age,
      pg.pgc_score
    FROM first_icu_stay f
    INNER JOIN pgc_calc pg ON f.stay_id = pg.stay_id
  ) o
),

quintiles AS (
  -- Stratify into quintiles and aggregate (now grouping by pre-computed quintile)
  SELECT 
    quintile,
    AVG(los) AS avg_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_pct,
    AVG(CAST(readmit_30d AS INT64)) * 100 AS readmit_rate_pct,
    COUNT(*) AS n_patients
  FROM outcomes_with_quintiles
  GROUP BY quintile
  ORDER BY quintile
),

patient_data AS (
  -- Extract data for 42yo (first matching stay)
  SELECT 
    subject_id,
    stay_id,
    pgc_score,
    quintile,
    los,
    hospital_expire_flag,
    readmit_30d
  FROM outcomes_with_quintiles
  WHERE anchor_age = 42
  LIMIT 1
),

patient_risk AS (
  -- Map patient to quintile outcomes
  SELECT 
    pd.subject_id,
    pd.quintile,
    pd.pgc_score,
    pd.los AS patient_los,
    pd.hospital_expire_flag AS patient_mortality,
    pd.readmit_30d AS patient_readmit,
    q.avg_los_days AS estimated_los,
    q.mortality_rate_pct AS estimated_mortality_pct,
    q.readmit_rate_pct AS estimated_readmit_pct
  FROM patient_data pd
  INNER JOIN quintiles q ON pd.quintile = q.quintile
)

-- Report quintile summaries
SELECT 
  'Quintile Summary' AS report_type,
  quintile,
  ROUND(avg_los_days, 2) AS avg_los_days,
  ROUND(mortality_rate_pct, 2) AS mortality_rate_pct,
  ROUND(readmit_rate_pct, 2) AS readmit_rate_pct,
  n_patients
FROM quintiles

UNION ALL

-- Patient-specific estimate
SELECT 
  'Patient Risk Estimate (42yo Male)' AS report_type,
  pr.quintile,
  ROUND(pr.estimated_los, 2) AS avg_los_days,
  ROUND(pr.estimated_mortality_pct, 2) AS mortality_rate_pct,
  ROUND(pr.estimated_readmit_pct, 2) AS readmit_rate_pct,
  1 AS n_patients
FROM patient_risk pr;