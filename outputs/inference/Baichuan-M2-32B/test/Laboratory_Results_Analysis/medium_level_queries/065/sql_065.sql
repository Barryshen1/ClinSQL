WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 49 AND 59
),
eligible_admissions AS (
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    ep.admittime
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON ep.subject_id = d.subject_id AND ep.hadm_id = d.hadm_id
  WHERE ep.rn = 1
    AND d.seq_num = 1
    AND d.icd_code IN ('I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9')
    AND d.icd_version = 10
),
troponin_events AS (
  SELECT 
    e.subject_id,
    e.hadm_id,
    e.charttime,
    e.valuenum,
    ROW_NUMBER() OVER (PARTITION BY e.subject_id, e.hadm_id ORDER BY e.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
    ON e.itemid = d.itemid
  WHERE d.label LIKE '%troponin T%'
    AND e.valueuom = 'ng/mL'
    AND e.valuenum > 0.04
),
troponin_values AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    t.valuenum AS initial_troponin
  FROM eligible_admissions a
  INNER JOIN troponin_events t 
    ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  WHERE t.rn = 1
),
stats AS (
  SELECT 
    APPROX_QUANTILES(initial_troponin, 4) AS quartiles
  FROM troponin_values
)
SELECT 
  quartiles[OFFSET(2)] AS median,
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS iqr
FROM stats;