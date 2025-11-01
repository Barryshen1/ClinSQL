WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),
admissions_with_chest_pain AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.long_title LIKE '%chest pain%'
    AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
),
troponin_labs AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  WHERE dl.label LIKE '%TROPONIN I%'
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND l.charttime BETWEEN a.admittime AND a.dischtime
),
first_troponin AS (
  SELECT hadm_id, valuenum
  FROM troponin_labs
  WHERE rn = 1
    AND valuenum > ref_range_upper
),
combined AS (
  SELECT f.valuenum
  FROM admissions_with_chest_pain a
  INNER JOIN first_troponin f
    ON a.hadm_id = f.hadm_id
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MIN(valuenum) AS min,
  MAX(valuenum) AS max
FROM combined;