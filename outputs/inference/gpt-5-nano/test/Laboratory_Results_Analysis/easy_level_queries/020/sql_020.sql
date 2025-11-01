WITH hf_male_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND LOWER(dd.long_title) LIKE '%heart failure%'
)

-- 2) per-admission nadir hemoglobin
, nadir_by_hadm AS (
  SELECT h.hadm_id,
         MIN(lv.valuenum) AS nadir_hemoglobin
  FROM hf_male_admissions AS h
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS lv
    ON lv.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON lv.itemid = dli.itemid
  WHERE lv.valuenum IS NOT NULL
    AND LOWER(dli.label) LIKE '%hemoglobin%'
  GROUP BY h.hadm_id
)

-- 3) 75th percentile of nadir Hb across HF male admissions
SELECT quantiles[OFFSET(75)] AS p75_nadir_hemoglobin
FROM (
  SELECT APPROX_QUANTILES(nadir_hemoglobin, 100) AS quantiles
  FROM nadir_by_hadm
  WHERE nadir_hemoglobin IS NOT NULL
) AS t;