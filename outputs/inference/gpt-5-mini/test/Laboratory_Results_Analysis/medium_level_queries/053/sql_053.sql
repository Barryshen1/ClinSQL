WITH troponin_i_items AS (
  -- identify lab itemids that correspond to Troponin I
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),

first_troponin_per_adm AS (
  -- for each admission, take the earliest Troponin I measurement (in ng/mL)
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS initial_troponin,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.storetime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_i_items t ON le.itemid = t.itemid
  WHERE le.hadm_id IS NOT NULL
    AND le.valuenum IS NOT NULL
    -- require units mention 'ng' (to align with ng/mL threshold). Adjust if your data uses different unit text.
    AND (le.valueuom IS NOT NULL AND LOWER(le.valueuom) LIKE '%ng%')
),

acs_admissions AS (
  -- admissions flagged with diagnoses likely representing ACS (text-based)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE (
    LOWER(dd.long_title) LIKE '%acute coronary%'
    OR LOWER(dd.long_title) LIKE '%acute myocardial%'
    OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
    OR LOWER(dd.long_title) LIKE '%unstable angina%'
    OR LOWER(dd.long_title) LIKE '%stemi%'
    OR LOWER(dd.long_title) LIKE '%nstemi%'
    OR LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
  )
),

eligible_admissions AS (
  -- female patients aged between 68 and 78 on admission who have an ACS diagnosis
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN acs_admissions acs
    ON a.hadm_id = acs.hadm_id
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 68 AND 78
),

initial_troponin_values AS (
  -- keep only the first troponin measurement per admission
  SELECT ftp.subject_id, ftp.hadm_id, ftp.initial_troponin
  FROM first_troponin_per_adm ftp
  WHERE ftp.rn = 1
)

SELECT
  COUNT(DISTINCT ea.subject_id) AS patient_count,
  COUNT(DISTINCT ea.hadm_id) AS admission_count,
  ROUND(AVG(itv.initial_troponin), 4) AS mean_initial_troponin,
  ROUND(STDDEV_SAMP(itv.initial_troponin), 4) AS sd_initial_troponin,
  MIN(itv.initial_troponin) AS min_initial_troponin,
  MAX(itv.initial_troponin) AS max_initial_troponin
FROM eligible_admissions ea
JOIN initial_troponin_values itv
  ON ea.hadm_id = itv.hadm_id
WHERE itv.initial_troponin > 0.04;