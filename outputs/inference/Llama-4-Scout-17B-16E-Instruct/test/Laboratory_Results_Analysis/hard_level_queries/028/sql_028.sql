WITH 
-- Identify patients with ICH, female, 74-84 years old
patients_ich AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 74 AND 84
    AND d.icd_code IN ('907.0', '431', '432.0', '432.1', '432.9')  -- ICH codes
),

-- Get lab events for initial 72 hours
lab_events_72h AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.itemid, 
    le.charttime,
    le.value,
    le.valuenum,
    le.valueuom,
    pich.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    patients_ich pich 
      ON le.subject_id = pich.subject_id AND le.hadm_id = pich.hadm_id
  WHERE 
    le.charttime BETWEEN pich.admittime AND TIMESTAMP_ADD(pich.admittime, INTERVAL 72 HOUR)
),

-- Identify abnormal labs
abnormal_labs AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    COUNT(DISTINCT le.itemid) AS distinct_abnormal_labs
  FROM 
    lab_events_72h le
  WHERE 
    le.valuenum IS NOT NULL 
    AND (le.valueuom != '' OR le.value != '')
    AND (  -- Example abnormal lab ranges, update as needed
      (le.itemid = 220050) AND (le.valuenum < 3.5 OR le.valuenum > 5.5)  -- Potassium
      OR (le.itemid = 220179) AND (le.valuenum < 70 OR le.valuenum > 140)  -- Glucose
      OR (le.itemid = 220052) AND (le.valuenum < 36 OR le.valuenum > 45)  -- Bicarbonate
    )
  GROUP BY 
    le.subject_id, 
    le.hadm_id
),

-- Stratify into quintiles
quintiles AS (
  SELECT 
    subject_id, 
    hadm_id, 
    distinct_abnormal_labs,
    NTILE(5) OVER (ORDER BY distinct_abnormal_labs) AS quintile
  FROM 
    abnormal_labs
),

-- Calculate mortality and mean LOS by quintile
mortality_los AS (
  SELECT 
    q.quintile, 
    AVG(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los
  FROM 
    quintiles q
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
  GROUP BY 
    q.quintile
)

SELECT 
  *
FROM 
  mortality_los
ORDER BY 
  quintile;