WITH 
-- Identify cohort
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type = 'I'
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE '433%'  -- Acute ischemic stroke ICD code
    )
),

-- Calculate LOS
cohort_los AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(COALESCE(dischtime, deathtime), admittime, DAY) AS los
  FROM 
    cohort
),

-- Hospital mortality
cohort_mortality AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN dischtime IS NULL AND deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS hospital_death
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM cohort)
),

-- Critical lab events
critical_labs AS (
  SELECT 
    hadm_id,
    charttime,
    itemid,
    value,
    valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM cohort)
    AND itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE category = 'Blood gases' OR category = 'Electrolytes')
),

-- Simplified lab instability score (e.g., number of critical lab events within 72 hours of admission)
lab_instability AS (
  SELECT 
    hadm_id,
    COUNT(*) AS critical_lab_events
  FROM 
    critical_labs
  WHERE 
    charttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 3 DAY)
  GROUP BY 
    hadm_id
)

-- Final query
SELECT 
  COALESCE(AVG(cl.los), 0) AS avg_los,
  COALESCE(SUM(cm.hospital_death) / COUNT(cm.hadm_id), 0) AS hospital_mortality_rate,
  COALESCE(MIN(li.critical_lab_events), 0) AS min_72hr_lab_instability_score
FROM 
  cohort_los cl
  JOIN cohort_mortality cm 
  USING (hadm_id)
  LEFT JOIN lab_instability li
  USING (hadm_id);