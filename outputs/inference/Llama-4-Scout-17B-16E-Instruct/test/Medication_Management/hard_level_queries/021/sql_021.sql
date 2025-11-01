WITH 
-- Identify population of interest
population AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 41 AND 51
),

-- Identify patients with neutropenia and fever
neutropenia_fever AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid IN (
      220050, 220179
    ) 
    AND valuenum < 1000 
    AND charttime BETWEEN (SELECT MIN(admittime) FROM population) AND (SELECT MAX(dischtime) FROM population)
),

-- Medications prescribed in first 48 hours
medications AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    COUNT(DISTINCT p.drug) AS unique_medications
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN 
    population po 
      ON p.subject_id = po.subject_id AND p.hadm_id = po.hadm_id
  WHERE 
    p.starttime BETWEEN po.admittime AND po.admittime + INTERVAL 2 DAY
  GROUP BY 
    p.subject_id, 
    p.hadm_id
),

-- Combine population, neutropenia/fever, and medications
combined AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    m.unique_medications
  FROM 
    population p
  JOIN 
    neutropenia_fever n 
      ON p.subject_id = n.subject_id AND p.hadm_id = n.hadm_id
  JOIN 
    medications m 
      ON p.subject_id = m.subject_id AND p.hadm_id = m.hadm_id
),

-- Calculate tertiles of unique medications
tertiles AS (
  SELECT 
    subject_id, 
    hadm_id, 
    unique_medications,
    NTILE(3) OVER (ORDER BY unique_medications) AS tertile
  FROM 
    combined
),

-- Calculate LOS, in-hospital mortality, and 30-day readmission
outcomes AS (
  SELECT 
    t.subject_id, 
    t.hadm_id,
    TIMESTAMP_DIFF(po.dischtime, po.admittime, DAY) AS los,
    IF(po.hospital_expire_flag = 1, 1, 0) AS in_hospital_death,
    CASE 
      WHEN EXISTS (
        SELECT 
          1 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE 
          a2.subject_id = t.subject_id 
          AND a2.admittime BETWEEN po.dischtime AND TIMESTAMP_ADD(po.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM 
    tertiles t
  JOIN 
    population po 
      ON t.subject_id = po.subject_id AND t.hadm_id = po.hadm_id
)

-- Final aggregation
SELECT 
  tertile,
  AVG(los) AS avg_los,
  AVG(in_hospital_death) AS in_hospital_mortality_rate,
  AVG(readmitted) AS thirty_day_readmission_rate
FROM 
  outcomes
GROUP BY 
  tertile;