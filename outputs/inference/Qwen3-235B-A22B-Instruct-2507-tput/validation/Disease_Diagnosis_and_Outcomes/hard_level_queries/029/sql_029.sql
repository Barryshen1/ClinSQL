WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    a.hospital_expire_flag AS in_hospital_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 82 AND 92
),
pneumonia_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pneumonia%'
    AND di.seq_num = 1  -- primary diagnosis
),
diagnosis_counts AS (
  SELECT
    pa.hadm_id,
    COUNT(DISTINCT di.icd_code) AS diagnosis_count
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  GROUP BY pa.hadm_id
),
complication_flags AS (
  SELECT
    pa.hadm_id,
    MAX(CASE
      WHEN LOWER(d.long_title) LIKE '%cardiac%' 
        OR LOWER(d.long_title) LIKE '%heart%' 
        OR LOWER(d.long_title) LIKE '%myocardial infarction%'
        OR LOWER(d.long_title) LIKE '%heart failure%'
        OR LOWER(d.long_title) LIKE '%arrhythmia%'
        OR LOWER(d.long_title) LIKE '%hypertension%' THEN 1
      ELSE 0
    END) AS has_cardiovascular_complication,
    MAX(CASE
      WHEN LOWER(d.long_title) LIKE '%neuro%' 
        OR LOWER(d.long_title) LIKE '%stroke%'
        OR LOWER(d.long_title) LIKE '%seizure%'
        OR LOWER(d.long_title) LIKE '%convulsion%'
        OR LOWER(d.long_title) LIKE '%encephalopathy%'
        OR LOWER(d.long_title) LIKE '%delirium%' THEN 1
      ELSE 0
    END) AS has_neurologic_complication
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY pa.hadm_id
),
mortality_los AS (
  SELECT
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.dod,
    DATETIME_ADD(pa.admittime, INTERVAL 30 DAY) AS thirty_day_cutoff,
    CASE
      WHEN pa.in_hospital_death = 1 THEN 1
      WHEN pa.dod IS NOT NULL AND pa.dod <= DATETIME_ADD(pa.admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS thirty_day_mortality,
    CASE
      WHEN pa.in_hospital_death = 0 AND (pa.dod IS NULL OR pa.dod > DATETIME_ADD(pa.admittime, INTERVAL 30 DAY))
      THEN DATETIME_DIFF(pa.dischtime, pa.admittime, HOUR) / 24.0
      ELSE NULL
    END AS los_days_if_survivor
  FROM pneumonia_admissions pa
),
risk_quintiles AS (
  SELECT
    pa.hadm_id,
    dc.diagnosis_count,
    NTILE(5) OVER (ORDER BY dc.diagnosis_count) AS risk_quintile
  FROM pneumonia_admissions pa
  JOIN diagnosis_counts dc ON pa.hadm_id = dc.hadm_id
)
SELECT
  rq.risk_quintile,
  AVG(m.thirty_day_mortality) AS thirty_day_mortality_rate,
  AVG(cf.has_cardiovascular_complication) AS cardiovascular_complication_rate,
  AVG(cf.has_neurologic_complication) AS neurologic_complication_rate,
  APPROX_QUANTILES(m.los_days_if_survivor, 100)[OFFSET(50)] AS median_los_days_survivors
FROM risk_quintiles rq
JOIN mortality_los m ON rq.hadm_id = m.hadm_id
JOIN complication_flags cf ON rq.hadm_id = cf.hadm_id
GROUP BY rq.risk_quintile
ORDER BY rq.risk_quintile;