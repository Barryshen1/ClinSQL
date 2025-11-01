WITH patient_icu AS (
  SELECT 
    s.subject_id,
    s.stay_id,
    s.intime,
    s.los,
    s.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM s.intime) - p.anchor_year AS age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON s.subject_id = p.subject_id
),
first_stays AS (
  SELECT 
    subject_id,
    stay_id,
    intime,
    los,
    hadm_id,
    gender,
    anchor_age,
    anchor_year,
    age
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
    FROM 
      patient_icu
  ) 
  WHERE rn = 1
),
dialysis_subjects AS (
  SELECT DISTINCT 
    pe.subject_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON pe.itemid = di.itemid
  WHERE 
    LOWER(di.label) LIKE '%dialysis%'
    OR LOWER(di.label) LIKE '%crrt%'
    OR LOWER(di.label) LIKE '%cvvh%'
    OR LOWER(di.label) LIKE '%cvvhd%'
    OR LOWER(di.label) LIKE '%sled%'
    OR LOWER(di.label) LIKE '%rrt%'
),
cohort AS (
  SELECT 
    fs.los
  FROM 
    first_stays fs
  INNER JOIN 
    dialysis_subjects ds 
    ON fs.subject_id = ds.subject_id
  WHERE 
    fs.gender = 'F' 
    AND fs.age >= 77 
    AND fs.age <= 87
)
SELECT 
  q[OFFSET(1)] AS q1,
  q[OFFSET(3)] AS q3,
  q[OFFSET(3)] - q[OFFSET(1)] AS iqr
FROM (
  SELECT 
    APPROX_QUANTILES(los, 4) AS q
  FROM 
    cohort
);