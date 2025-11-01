WITH 
-- Identify ICU patients with sepsis
sepsis_patients AS (
  SELECT 
    ic.stay_id,
    ic.subject_id,
    ic.hadm_id,
    ic.intime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 53 AND 63
    AND ic.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN ('995.91', '785.59', '038.0', '038.1', '038.2', '038.3', '038.4', '038.5', '038.6', '038.7', '038.8', '038.9')
    )
),

-- Identify procedures in the first 24 hours
procedures_first_24_hours AS (
  SELECT 
    sp.hadm_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM 
    sepsis_patients sp
  JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
      ON sp.stay_id = pe.stay_id
  WHERE 
    pe.starttime BETWEEN sp.intime AND TIMESTAMP_ADD(sp.intime, INTERVAL 24 HOUR)
  GROUP BY 
    sp.hadm_id
),

-- Calculate percentiles of procedures
percentiles AS (
  SELECT 
    APPROX_QUANTILES(num_procedures, 0.75) AS percentile_75,
    APPROX_QUANTILES(num_procedures, 0.9) AS percentile_90
  FROM 
    procedures_first_24_hours
),

-- Age-matched ICU patients without sepsis
age_matched_without_sepsis AS (
  SELECT 
    ic.stay_id,
    ic.subject_id,
    ic.hadm_id,
    ic.intime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 53 AND 63
    AND ic.hadm_id NOT IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN ('995.91', '785.59', '038.0', '038.1', '038.2', '038.3', '038.4', '038.5', '038.6', '038.7', '038.8', '038.9')
    )
),

-- Calculate average ICU LOS and hospital mortality
icu_los_mortality AS (
  SELECT 
    'Sepsis' AS category,
    AVG(TIMESTAMP_DIFF(ic.outtime, ic.intime, HOUR)) / 24 AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(a.hadm_id) AS hospital_mortality
  FROM 
    sepsis_patients sp
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON sp.stay_id = ic.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON sp.hadm_id = a.hadm_id

  UNION ALL

  SELECT 
    'Age-matched without sepsis' AS category,
    AVG(TIMESTAMP_DIFF(ic.outtime, ic.intime, HOUR)) / 24 AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(a.hadm_id) AS hospital_mortality
  FROM 
    age_matched_without_sepsis amws
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON amws.stay_id = ic.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON amws.hadm_id = a.hadm_id
)

SELECT 
  (SELECT percentile_75[OFFSET(0)] FROM percentiles) AS percentile_75,
  (SELECT percentile_90[OFFSET(0)] FROM percentiles) AS percentile_90,
  ilm.category,
  ilm.avg_icu_los,
  ilm.hospital_mortality
FROM 
  percentiles, 
  icu_los_mortality ilm;