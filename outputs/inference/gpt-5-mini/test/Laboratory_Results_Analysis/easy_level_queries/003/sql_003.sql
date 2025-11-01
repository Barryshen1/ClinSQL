WITH acs_hads AS (
  -- admissions with an ACS-related diagnosis
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
   AND d.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%myocardial infarction%'
     OR LOWER(dic.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(dic.long_title) LIKE '%unstable angina%'
     OR LOWER(dic.long_title) LIKE '%stemi%'
     OR LOWER(dic.long_title) LIKE '%nstemi%'
     OR LOWER(dic.long_title) LIKE '%infarction%'
),
male_64_acs_admissions AS (
  -- male patients age ~64 with ACS admissions
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 64
    AND a.hadm_id IN (SELECT hadm_id FROM acs_hads)
),
troponin_items AS (
  -- lab itemids that look like troponin assays
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
),
peaks AS (
  -- peak troponin per admission (in-hospital labevents linked by hadm_id)
  SELECT
    m.subject_id,
    m.hadm_id,
    MAX(le.valuenum) AS peak_troponin
  FROM male_64_acs_admissions m
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON m.hadm_id = le.hadm_id
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
  GROUP BY m.subject_id, m.hadm_id
)
SELECT
  COUNT(*) AS num_admissions,
  -- approximate 75th percentile
  APPROX_QUANTILES(peak_troponin, 100)[OFFSET(75)] AS troponin_p75
FROM peaks
WHERE peak_troponin IS NOT NULL;