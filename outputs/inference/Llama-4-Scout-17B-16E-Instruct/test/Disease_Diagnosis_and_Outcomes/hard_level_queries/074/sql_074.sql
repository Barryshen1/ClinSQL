WITH 
  -- Identify PE patients
  pe_patients AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE '415%'
  ),
  
  -- Calculate comorbidity burden (example using DRG severity)
  comorbidity_burden AS (
    SELECT subject_id, hadm_id, drg_severity
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  ),
  
  -- Filter male patients aged 79-89
  target_patients AS (
    SELECT p.subject_id, p.anchor_age, p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 79 AND 89
  ),
  
  -- Combine PE, comorbidity, and demographics
  target_group AS (
    SELECT tp.subject_id, tp.anchor_age, tp.gender, 
           cb.drg_severity
    FROM target_patients tp
    JOIN pe_patients pp ON tp.subject_id = pp.subject_id
    JOIN comorbidity_burden cb ON pp.hadm_id = cb.hadm_id
  ),
  
  -- Calculate 30-day mortality and complications (example)
  outcomes AS (
    SELECT 
      CASE 
        WHEN a.deathtime IS NOT NULL AND a.deathtime <= TIMESTAMP_ADD(a.admittime, INTERVAL 30 DAY) THEN 1
        ELSE 0
      END AS thirty_day_mortality,
      -- Add complication checks here
      a.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  )

-- Final query for specific patient and group statistics
SELECT 
  tg.subject_id,
  PERCENT_RANK() OVER (ORDER BY tg.drg_severity) AS comorbidity_percentile,
  AVG(o.thirty_day_mortality) AS thirty_day_mortality_rate,
  -- Add more outcome measures here
FROM target_group tg
JOIN outcomes o ON tg.subject_id = o.subject_id
GROUP BY tg.subject_id, tg.drg_severity;