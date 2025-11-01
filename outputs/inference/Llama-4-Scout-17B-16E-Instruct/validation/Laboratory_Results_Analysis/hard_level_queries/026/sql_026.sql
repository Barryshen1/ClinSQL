WITH 
-- Define the cohort of male inpatients aged 75-85 with hepatic failure
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_type = 'Inpatient'
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code LIKE '%785.4%'  -- Verify this ICD code for hepatic failure
    )
),

-- Calculate maximum instability score within the first 48 hours
instability AS (
  SELECT 
    ce.hadm_id,
    MAX(ce.valuenum) AS max_instability_score
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    cohort c ON ce.hadm_id = c.hadm_id
  WHERE 
    ce.itemid = 220050  -- Verify this itemid for instability score
    AND ce.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY 
    ce.hadm_id
),

-- Calculate mortality
mortality AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN dischtime IS NULL AND deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS died_in_hospital
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Calculate average LOS
los AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Critical lab frequencies
labs AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT itemid) AS lab_frequency
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY 
    hadm_id
),

-- General inpatient comparison
general_inpatients AS (
  SELECT 
    COUNT(DISTINCT hadm_id) AS total_inpatients
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` 
  WHERE 
    admission_type = 'Inpatient'
),

cohort_inpatients AS (
  SELECT 
    COUNT(DISTINCT hadm_id) AS total_cohort_inpatients
  FROM 
    cohort
)

SELECT 
  COALESCE(MAX(i.max_instability_score), 0) AS max_instability_score,
  COALESCE(SUM(m.died_in_hospital) / NULLIF(COUNT(m.hadm_id), 0), 0) AS mortality_rate,
  COALESCE(AVG(l.los), 0) AS avg_los,
  COALESCE(AVG(lab.lab_frequency), 0) AS avg_lab_frequency,
  COALESCE(
    (SELECT total_cohort_inpatients FROM cohort_inpatients) / 
    NULLIF((SELECT total_inpatients FROM general_inpatients), 0), 
    0
  ) AS cohort_to_general_inpatient_ratio
FROM 
  cohort c
  LEFT JOIN instability i ON c.hadm_id = i.hadm_id
  LEFT JOIN mortality m ON c.hadm_id = m.hadm_id
  LEFT JOIN los l ON c.hadm_id = l.hadm_id
  LEFT JOIN labs lab ON c.hadm_id = lab.hadm_id;