WITH patients_with_age AS (
  SELECT 
    subject_id,
    gender,
    anchor_year,
    anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    -- Approximate age at admission: anchor_age + (year of admission - anchor_year)
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_with_age p ON a.subject_id = p.subject_id
),
pe_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    a.age_at_admission
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE 
    a.gender = 'M'
    AND a.age_at_admission = 84
    AND d.icd_code LIKE 'I26.%'  -- pulmonary embolism
),
icu_stays_pe AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN pe_admissions a 
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  -- Get the first ICU stay per admission (by intime)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
),
dus_pe AS (
  SELECT 
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.los,
    s.hospital_expire_flag,
    -- Count distinct lab itemids in first 24h
    (SELECT COUNT(DISTINCT itemid) 
     FROM `physionet-data.mimiciv_3_1_icu.labevents` l
     WHERE l.subject_id = s.subject_id
       AND l.hadm_id = s.hadm_id
       AND l.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    ) AS lab_count,
    -- Count distinct microbiology test itemids in first 24h
    (SELECT COUNT(DISTINCT test_itemid) 
     FROM `physionet-data.mimiciv_3_1_icu.microbiologyevents` m
     WHERE m.subject_id = s.subject_id
       AND m.hadm_id = s.hadm_id
       AND m.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    ) AS micro_count,
    -- DUS = lab_count + micro_count
    COALESCE((SELECT COUNT(DISTINCT itemid) 
              FROM `physionet-data.mimiciv_3_1_icu.labevents` l
              WHERE l.subject_id = s.subject_id
                AND l.hadm_id = s.hadm_id
                AND l.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
             ), 0) 
    +
    COALESCE((SELECT COUNT(DISTINCT test_itemid) 
              FROM `physionet-data.mimiciv_3_1_icu.microbiologyevents` m
              WHERE m.subject_id = s.subject_id
                AND m.hadm_id = s.hadm_id
                AND m.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
             ), 0) AS dus
  FROM icu_stays_pe s
),
pe_group_stats AS (
  SELECT 
    APPROX_QUANTILES(dus, 100)[SAFE_OFFSET(75)] AS pe_group_dus_75th_percentile,
    AVG(los) AS pe_group_los_mean,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS pe_group_mortality_rate
  FROM dus_pe
),
general_icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
general_icu_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN general_icu_stays g ON a.hadm_id = g.hadm_id
),
general_icu_stats AS (
  SELECT 
    AVG(g.los) AS general_icu_los_mean,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS general_icu_mortality_rate
  FROM general_icu_stays g
  INNER JOIN general_icu_admissions a ON g.hadm_id = a.hadm_id
)
SELECT 
  pe.pe_group_dus_75th_percentile,
  pe.pe_group_los_mean,
  pe.pe_group_mortality_rate,
  gen.general_icu_los_mean,
  gen.general_icu_mortality_rate
FROM pe_group_stats pe, general_icu_stats gen;