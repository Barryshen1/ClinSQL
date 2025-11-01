WITH base_cohort AS (
  SELECT 
    p.subject_id, 
    p.gender,
    a.hadm_id,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
),
dx_cohort AS (
  SELECT 
    bc.*
  FROM base_cohort bc
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE 
      d.hadm_id = bc.hadm_id
      AND (
        -- ICD-10 codes for chest pain or AMI
        (d.icd_version = 10 AND (d.icd_code LIKE 'R07%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        OR 
        -- ICD-9 codes for chest pain or AMI
        (d.icd_version = 9 AND (d.icd_code LIKE '786.5%' OR d.icd_code LIKE '410%'))
      )
  )
),
troponin_events AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_t_value,
    l.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE 
    l.itemid = 51003  -- Troponin T (itemid 51003, unit ng/mL)
    AND l.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    hadm_id,
    troponin_t_value,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM troponin_events
),
final_cohort AS (
  SELECT 
    dc.*,
    ft.troponin_t_value AS initial_troponin_t
  FROM dx_cohort dc
  INNER JOIN first_troponin ft
    ON dc.hadm_id = ft.hadm_id
    AND ft.rn = 1  -- First Troponin T measurement per admission
    AND ft.troponin_t_value > 0.04  -- Filter for values >0.04 ng/mL
)
SELECT 
  COUNT(DISTINCT hadm_id) AS num_admissions,
  COUNT(DISTINCT subject_id) AS num_patients,
  ROUND(AVG(age_at_admission), 1) AS avg_age,
  SUM(hospital_expire_flag) AS mortality_count,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(hadm_id), 2) AS mortality_rate_percent
FROM final_cohort;