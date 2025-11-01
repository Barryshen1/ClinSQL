WITH patient_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
),

diagnosis_filtered AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN di.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN di.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),

cohort AS (
  SELECT pa.*
  FROM patient_admissions pa
  JOIN diagnosis_filtered df
    ON pa.hadm_id = df.hadm_id
  WHERE df.has_t2dm = 1
    AND df.has_hf = 1
),

glp1_drugs AS (
  SELECT DISTINCT hadm_id,
    starttime,
    COALESCE(stoptime, dischtime) AS stoptime,
    admittime,
    dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c USING (hadm_id)
  WHERE LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%lixisenatide%'
),

cohort_with_flags AS (
  SELECT
    c.hadm_id,
    -- Flag: started within 72h of admission
    MAX(CASE WHEN g.starttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
              AND g.starttime >= c.admittime THEN 1 ELSE 0 END) AS started_early,
    -- Flag: on GLP-1 in last 48h (overlap with [dischtime - 48h, dischtime])
    MAX(CASE WHEN g.stoptime > DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)
              AND g.starttime < c.dischtime THEN 1 ELSE 0 END) AS on_late
  FROM cohort c
  LEFT JOIN glp1_drugs g ON c.hadm_id = g.hadm_id
  GROUP BY c.hadm_id
)

SELECT
  100.0 * SUM(started_early) / COUNT(*) AS pct_started_early,
  100.0 * SUM(on_late) / COUNT(*) AS pct_on_late,
  (100.0 * SUM(on_late) / COUNT(*) - 100.0 * SUM(started_early) / COUNT(*)) AS net_change
FROM cohort_with_flags;