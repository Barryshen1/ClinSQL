WITH 
  admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.admission_type,
      a.admit_provider_id,
      a.admission_location,
      a.discharge_location,
      a.insurance,
      a.language,
      a.marital_status,
      a.race,
      a.edregtime,
      a.edouttime,
      a.hospital_expire_flag,
      p.gender,
      p.anchor_age,
      p.anchor_year,
      p.anchor_year_group,
      p.dod
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),
  stroke_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      a.anchor_age,
      a.gender
    FROM 
      admissions a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      a.hadm_id = d.hadm_id
    WHERE 
      d.icd_code LIKE '433%'  -- Ischemic stroke ICD code
      AND a.anchor_age = 94
      AND a.gender = 'M'
  ),
  glucose_values AS (
    SELECT 
      l.valuenum
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN 
      stroke_admissions s
    ON 
      l.hadm_id = s.hadm_id
    WHERE 
      l.itemid = 220050  -- Serum glucose
      AND l.charttime >= s.dischtime - INTERVAL 1 DAY
      AND l.charttime <= s.dischtime + INTERVAL 1 DAY
  )

SELECT 
  PERCENTILE_CONT(0.75)(valuenum) - PERCENTILE_CONT(0.25)(valuenum) AS IQR
FROM 
  glucose_values;