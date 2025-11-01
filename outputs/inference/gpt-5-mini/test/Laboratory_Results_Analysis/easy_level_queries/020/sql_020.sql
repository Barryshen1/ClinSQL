WITH hf_adm AS (
  -- admissions that have any heart-failure diagnosis (ICD long_title contains 'heart failure'
  -- or common ICD prefixes for HF in case long_title misses variations)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
     OR di.icd_code LIKE 'I50%'   -- ICD-10 heart failure codes
     OR di.icd_code LIKE '428%'   -- ICD-9 heart failure codes
),

cohort_adm AS (
  -- male, 49-year-old patients with a heart-failure admission
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hf_adm h
    ON a.hadm_id = h.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 49
),

hb_items AS (
  -- lab itemids that look like hemoglobin measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%hemoglobin%'
),

hb_vals AS (
  -- hemoglobin numeric measurements during the hospital stay for cohort admissions
  SELECT
    c.hadm_id,
    le.valuenum,
    le.valueuom,
    le.charttime
  FROM cohort_adm c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = c.hadm_id
  JOIN hb_items hi
    ON le.itemid = hi.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime BETWEEN c.admittime AND c.dischtime
),

nadir_per_adm AS (
  -- nadir (minimum) hemoglobin per admission
  SELECT hadm_id, MIN(valuenum) AS nadir_hb
  FROM hb_vals
  GROUP BY hadm_id
)

-- 75th percentile of the admission-level nadir hemoglobin (approximate)
SELECT
  COUNT(*) AS n_admissions_with_hb,
  APPROX_QUANTILES(nadir_hb, 100)[OFFSET(75)] AS pct75_nadir_hb
FROM nadir_per_adm;