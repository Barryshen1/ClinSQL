WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),
eligible_admissions AS (
  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ep.hadm_id = d.hadm_id
  WHERE d.icd_version = 10
    AND (d.icd_code LIKE 'R07%' OR d.icd_code LIKE 'I21%')
),
initial_tnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS tnt_value,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime, l.storetime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50341  -- hs-TnT itemid
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),
filtered_admissions AS (
  SELECT 
    ea.subject_id,
    ea.hadm_id,
    it.tnt_value
  FROM eligible_admissions ea
  INNER JOIN initial_tnt it
    ON ea.hadm_id = it.hadm_id
  WHERE it.rn = 1
    AND it.tnt_value > 0.014
)
SELECT 
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(tnt_value) AS mean_tnt,
  APPROX_QUANTILES(tnt_value, 100)[OFFSET(50)] AS median_tnt,
  APPROX_QUANTILES(tnt_value, 100)[OFFSET(75)] - APPROX_QUANTILES(tnt_value, 100)[OFFSET(25)] AS iqr_tnt
FROM filtered_admissions;