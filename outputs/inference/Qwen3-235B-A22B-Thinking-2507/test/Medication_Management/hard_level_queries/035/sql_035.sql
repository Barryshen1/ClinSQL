WITH patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 40 AND 50
),

neutropenia AS (
  SELECT DISTINCT
    le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN patients_filtered pf
    ON le.hadm_id = pf.hadm_id
  WHERE le.itemid = 51146  -- Absolute neutrophil count
    AND le.valuenum < 500
    AND le.charttime <= TIMESTAMP_ADD(pf.admittime, INTERVAL 48 HOUR)
),

fever AS (
  SELECT DISTINCT
    ce.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN patients_filtered pf
    ON ce.hadm_id = pf.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON ce.stay_id = ie.stay_id
  WHERE ce.itemid = 223761  -- Temperature Fahrenheit (101°F = 38.3°C)
    AND ce.valuenum >= 101.0
    AND ce.charttime <= TIMESTAMP_ADD(pf.admittime, INTERVAL 48 HOUR)
    AND ie.intime <= TIMESTAMP_ADD(pf.admittime, INTERVAL 48 HOUR)
),

neutropenic_fever AS (
  SELECT 
    pf.subject_id,
    pf.hadm_id,
    pf.admittime,
    pf.dischtime,
    pf.hospital_expire_flag
  FROM patients_filtered pf
  INNER JOIN neutropenia n ON pf.hadm_id = n.hadm_id
  INNER JOIN fever f ON pf.hadm_id = f.hadm_id
),

medication_complexity AS (
  SELECT 
    nf.hadm_id,
    COUNT(DISTINCT e.medication) AS medication_count
  FROM neutropenic_fever nf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON nf.hadm_id = e.hadm_id
    AND e.charttime <= TIMESTAMP_ADD(nf.admittime, INTERVAL 48 HOUR)
  GROUP BY nf.hadm_id
),

quartiles AS (
  SELECT 
    mc.hadm_id,
    mc.medication_count,
    NTILE(4) OVER (ORDER BY mc.medication_count) AS score_quartile
  FROM medication_complexity mc
),

readmissions AS (
  SELECT 
    a1.hadm_id AS index_admission,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM neutropenic_fever a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
    AND a1.hadm_id != a2.hadm_id
)

SELECT 
  q.score_quartile,
  COUNT(*) AS patient_count,
  AVG(q.medication_count) AS mean_score,
  MIN(q.medication_count) AS min_score,
  MAX(q.medication_count) AS max_score,
  AVG(TIMESTAMP_DIFF(nf.dischtime, nf.admittime, HOUR)/24.0) AS mean_los,
  (SUM(nf.hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_pct,
  (SUM(COALESCE(r.readmitted_30d, 0)) * 100.0 / 
   NULLIF(COUNT(*) - SUM(nf.hospital_expire_flag), 0)) AS readmission_30d_pct
FROM quartiles q
INNER JOIN neutropenic_fever nf ON q.hadm_id = nf.hadm_id
LEFT JOIN readmissions r ON q.hadm_id = r.index_admission
GROUP BY q.score_quartile
ORDER BY q.score_quartile;