WITH 
-- Filter patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 68 AND 78
    AND p.gender = 'M'
    AND a.hadm_id IN (
      SELECT 
        di.hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN 
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
          ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE 
        d.long_title IN ('Diabetes mellitus', 'Acute heart failure')
    )
),

-- Identify insulin and oral agent prescriptions
insulin_prescriptions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    starttime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    drug_type = 'Insulin'
),

oral_agent_prescriptions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    starttime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    drug_type NOT IN ('Insulin')  -- Assuming all other drug types are oral agents
),

-- Calculate time windows
first_24h AS (
  SELECT 
    hadm_id, 
    MIN(admittime) AS admission_time
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY 
    hadm_id
),

last_24h AS (
  SELECT 
    hadm_id, 
    MAX(dischtime) AS discharge_time
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY 
    hadm_id
)

-- Calculate initiation rates
SELECT 
  'Insulin First 24h' AS category,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN i.starttime BETWEEN f.admission_time AND TIMESTAMP_ADD(f.admission_time, INTERVAL 1 DAY) THEN i.hadm_id END), 
    COUNT(DISTINCT poi.hadm_id)
  ) * 100 AS initiation_rate
FROM 
  patients_of_interest poi
  JOIN first_24h f ON poi.hadm_id = f.hadm_id
  LEFT JOIN insulin_prescriptions i ON poi.hadm_id = i.hadm_id

UNION ALL

SELECT 
  'Oral Agent First 24h',
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN o.starttime BETWEEN f.admission_time AND TIMESTAMP_ADD(f.admission_time, INTERVAL 1 DAY) THEN o.hadm_id END), 
    COUNT(DISTINCT poi.hadm_id)
  ) * 100
FROM 
  patients_of_interest poi
  JOIN first_24h f ON poi.hadm_id = f.hadm_id
  LEFT JOIN oral_agent_prescriptions o ON poi.hadm_id = o.hadm_id

UNION ALL

SELECT 
  'Insulin Last 24h',
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN i.starttime BETWEEN TIMESTAMP_SUB(l.discharge_time, INTERVAL 1 DAY) AND l.discharge_time THEN i.hadm_id END), 
    COUNT(DISTINCT poi.hadm_id)
  ) * 100
FROM 
  patients_of_interest poi
  JOIN last_24h l ON poi.hadm_id = l.hadm_id
  LEFT JOIN insulin_prescriptions i ON poi.hadm_id = i.hadm_id

UNION ALL

SELECT 
  'Oral Agent Last 24h',
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN o.starttime BETWEEN TIMESTAMP_SUB(l.discharge_time, INTERVAL 1 DAY) AND l.discharge_time THEN o.hadm_id END), 
    COUNT(DISTINCT poi.hadm_id)
  ) * 100
FROM 
  patients_of_interest poi
  JOIN last_24h l ON poi.hadm_id = l.hadm_id
  LEFT JOIN oral_agent_prescriptions o ON poi.hadm_id = o.hadm_id;