WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 50 AND 60
),
eligible_admissions AS (
  SELECT DISTINCT e.subject_id, e.hadm_id
  FROM eligible_patients e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON e.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = 10
    AND (dd.icd_code LIKE 'I21.%' OR dd.icd_code = 'R07.9')
),
hs_tnt_labs AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS initial_hs_tnt
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl 
    ON l.itemid = dl.itemid
  WHERE dl.itemid = 51265  -- hs-TnT
    AND l.valuenum > 0.014  -- ULN
    AND l.valueuom = 'ng/mL'
),
first_hs_tnt AS (
  SELECT 
    h.subject_id,
    h.hadm_id,
    h.initial_hs_tnt
  FROM (
    SELECT 
      h.subject_id,
      h.hadm_id,
      h.initial_hs_tnt,
      ROW_NUMBER() OVER (PARTITION BY h.hadm_id ORDER BY h.charttime) AS rn
    FROM hs_tnt_labs h
    INNER JOIN eligible_admissions e 
      ON h.hadm_id = e.hadm_id
  ) h
  WHERE h.rn = 1
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(initial_hs_tnt) AS mean_initial_hs_tnt,
  APPROX_QUANTILES(initial_hs_tnt, 100)[OFFSET(50)] AS median_initial_hs_tnt,
  APPROX_QUANTILES(initial_hs_tnt, 100)[OFFSET(75)] - APPROX_QUANTILES(initial_hs_tnt, 100)[OFFSET(25)] AS iqr_initial_hs_tnt
FROM first_hs_tnt;