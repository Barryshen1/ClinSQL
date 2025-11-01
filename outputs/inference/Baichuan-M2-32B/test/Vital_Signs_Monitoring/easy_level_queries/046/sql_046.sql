WITH 
-- Step 1: Compute birth year and age at ICU admission for male patients
icu_stays_with_age AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    -- Compute birth year: anchor_year - anchor_age
    p.anchor_year - p.anchor_age AS birth_year,
    -- Age at ICU admission: year of intime minus birth_year
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'  -- male patients
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 37 AND 47
),

-- Step 2: Get the first SpO2 measurement per ICU stay
first_spo2_per_stay AS (
  SELECT 
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.age,
    -- Get the first chartevent after intime for SpO2
    MIN(c.charttime) AS first_spo2_time
  FROM 
    icu_stays_with_age s
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.subject_id = c.subject_id AND s.stay_id = c.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    d.category = 'Vitals' 
    AND (d.label LIKE '%SpO2%' OR d.label LIKE '%O2 saturation%')
    AND c.charttime >= s.intime  -- only after ICU admission
    AND c.valuenum IS NOT NULL   -- ensure we have a numeric value
  GROUP BY 
    s.stay_id, s.subject_id, s.hadm_id, s.intime, s.age
),

-- Step 3: Get the SpO2 value at the first measurement time per stay
spo2_values AS (
  SELECT 
    f.stay_id,
    f.subject_id,
    f.hadm_id,
    f.age,
    c.valuenum AS first_spo2
  FROM 
    first_spo2_per_stay f
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.subject_id = c.subject_id 
    AND f.stay_id = c.stay_id 
    AND f.first_spo2_time = c.charttime
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
    AND d.category = 'Vitals' 
    AND (d.label LIKE '%SpO2%' OR d.label LIKE '%O2 saturation%')
  WHERE 
    c.valuenum IS NOT NULL
),

-- Step 4: Compute the IQR of first_spo2
iqr_result AS (
  SELECT 
    APPROX_QUANTILES(first_spo2, 100) AS quartiles
  FROM 
    spo2_values
)

-- Step 5: Extract Q1, Q3, and IQR
SELECT 
  quartiles[OFFSET(25)] AS q1,  -- 25th percentile
  quartiles[OFFSET(75)] AS q3,  -- 75th percentile
  quartiles[OFFSET(75)] - quartiles[OFFSET(25)] AS iqr
FROM 
  iqr_result;