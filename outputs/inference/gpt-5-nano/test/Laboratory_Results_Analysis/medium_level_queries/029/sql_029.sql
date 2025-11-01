WITH chest_ami AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
    ON di.icd_code = dcd.icd_code
   AND di.icd_version = dcd.icd_version
  WHERE LOWER(dcd.long_title) LIKE '%chest pain%'
     OR LOWER(dcd.long_title) LIKE '%myocardial infarction%'
),
troponin_first AS (
  -- Identify admissions whose first Troponin T measurement has value > 0.04
  SELECT DISTINCT l.hadm_id
  FROM (
    SELECT hadm_id, MIN(charttime) AS first_charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
    WHERE LOWER(dl.label) LIKE '%troponin t%'
    GROUP BY hadm_id
  ) f
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.hadm_id = f.hadm_id
   AND l.charttime = f.first_charttime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%' AND l.valuenum > 0.04
),
Cohort AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN chest_ami ca ON ca.hadm_id = a.hadm_id
  JOIN troponin_first tf ON tf.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON p.subject_id = a.subject_id
  WHERE p.gender = 'Male'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
)

SELECT
  COUNT(DISTINCT c.hadm_id) AS n_admissions,
  COUNT(DISTINCT c.subject_id) AS n_patients,
  AVG(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS avg_age_at_adm,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 3600.0) AS avg_los_hours,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_rate
FROM Cohort c
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = c.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON p.subject_id = c.subject_id;