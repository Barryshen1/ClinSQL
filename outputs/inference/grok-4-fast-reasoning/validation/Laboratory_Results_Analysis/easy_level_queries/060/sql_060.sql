WITH glucose_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%glucose%'
    AND category = 'Chemistry'
),
pneumonia_adms AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON diag.icd_code = icd.icd_code
    AND diag.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND LOWER(icd.long_title) LIKE '%pneumonia%'
    AND a.hadm_id IS NOT NULL
),
mean_glucose_per_adm AS (
  SELECT pa.hadm_id, AVG(l.valuenum) AS mean_glucose
  FROM pneumonia_adms pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON pa.hadm_id = l.hadm_id
  INNER JOIN glucose_items gi
    ON l.itemid = gi.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.charttime >= pa.admittime
    AND l.charttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 1 DAY)
  GROUP BY pa.hadm_id
  HAVING COUNT(l.valuenum) >= 1
)
SELECT PERCENTILE_CONT(0.75) OVER (ORDER BY mean_glucose) AS p75th_percentile_mean_glucose
FROM mean_glucose_per_adm
LIMIT 1;