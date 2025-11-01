WITH first_tnt AS (
  SELECT 
    subject_id, 
    hadm_id, 
    FIRST_VALUE(valuenum) OVER (
      PARTITION BY subject_id, hadm_id 
      ORDER BY charttime ASC
    ) AS initial_tnt,
    FIRST_VALUE(charttime) OVER (
      PARTITION BY subject_id, hadm_id 
      ORDER BY charttime ASC
    ) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE le.itemid = 51009 
    AND le.valueuom = 'ng/mL'
    AND le.hadm_id IS NOT NULL
),
qualifying_adms AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    p.anchor_age, 
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 
       AND (d.icd_code LIKE '410.%' OR d.icd_code LIKE '786.5%'))
      OR 
      (d.icd_version = 10 
       AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07.%'))
    )
),
cohort AS (
  SELECT 
    qa.subject_id,
    qa.hadm_id,
    ft.initial_tnt,
    (qa.anchor_age + EXTRACT(YEAR FROM qa.admittime) - qa.anchor_year) AS age_at_adm
  FROM qualifying_adms qa
  JOIN first_tnt ft 
    ON qa.subject_id = ft.subject_id 
    AND qa.hadm_id = ft.hadm_id
  WHERE ft.initial_tnt > 0.014
    AND ft.first_charttime >= qa.admittime
    AND (qa.anchor_age + EXTRACT(YEAR FROM qa.admittime) - qa.anchor_year) BETWEEN 50 AND 60
)
SELECT 
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(initial_tnt) AS mean_initial_hs_tnt,
  APPROX_QUANTILES(initial_tnt, 2)[OFFSET(1)] AS median_initial_hs_tnt,
  (APPROX_QUANTILES(initial_tnt, 4)[OFFSET(3)] - APPROX_QUANTILES(initial_tnt, 4)[OFFSET(1)]) AS iqr_initial_hs_tnt
FROM cohort;