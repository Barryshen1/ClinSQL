WITH base_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 90 AND 100
),
chest_pain_admissions AS (
  SELECT DISTINCT ba.hadm_id
  FROM base_admissions ba
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ba.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chest pain%'
),
first_troponin AS (
  SELECT 
    cpa.hadm_id,
    l.valuenum,
    l.ref_range_upper,
    ROW_NUMBER() OVER (
      PARTITION BY cpa.hadm_id 
      ORDER BY l.charttime
    ) AS rn
  FROM chest_pain_admissions cpa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON cpa.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON l.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%troponin i%'
    AND LOWER(dli.fluid) = 'blood'
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),
elevated_troponin AS (
  SELECT hadm_id, valuenum
  FROM first_troponin
  WHERE rn = 1 AND valuenum > ref_range_upper
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val
FROM elevated_troponin;