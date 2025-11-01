WITH rr_data AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    AVG(CASE WHEN ce.valuenum IS NOT NULL THEN ce.valuenum END) AS avg_rr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ie.stay_id = ce.stay_id
    AND ce.itemid = 220210  -- Respiratory Rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
  GROUP BY ie.stay_id, ie.subject_id, ie.hadm_id
  HAVING avg_rr IS NOT NULL  -- only stays with at least one RR measurement
),
rr_categories AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
      WHEN avg_rr >= 30 THEN '>=30'
    END AS rr_category
  FROM rr_data
),
stroke_patients AS (
  SELECT DISTINCT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE dd.icd_code LIKE 'I63%' OR dd.icd_code LIKE 'I61%'
)
SELECT
  rc.rr_category,
  COUNT(rc.stay_id) AS number_of_stays,
  COUNT(DISTINCT CASE WHEN sp.hadm_id IS NOT NULL THEN rc.stay_id END) AS stroke_count
FROM rr_categories rc
LEFT JOIN stroke_patients sp
  ON rc.hadm_id = sp.hadm_id
GROUP BY rc.rr_category
ORDER BY rc.rr_category;