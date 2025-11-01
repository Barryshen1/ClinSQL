WITH cohort AS (
  SELECT 
    adm.hadm_id,
    pat.subject_id,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24*60*60) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 83 AND 93
),
troponin_first AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS initial_troponin_valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label LIKE '%Troponin T%'
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
)
SELECT 
  COUNT(*) AS N,
  AVG(cohort.age_at_admission) AS mean_age,
  AVG(cohort.hospital_los) AS mean_los,
  COUNT(tf.initial_troponin_valuenum) AS N_troponin,
  AVG(tf.initial_troponin_valuenum) AS mean_initial_troponin,
  MIN(tf.initial_troponin_valuenum) AS min_initial_troponin,
  MAX(tf.initial_troponin_valuenum) AS max_initial_troponin
FROM cohort
LEFT JOIN troponin_first tf
  ON cohort.hadm_id = tf.hadm_id;