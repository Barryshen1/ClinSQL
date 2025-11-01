WITH qualifying_admissions AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND EXTRACT(YEAR FROM a.admittime) >= 2008
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%')
),
initial_troponin AS (
  SELECT 
    le.hadm_id,
    MIN(CAST(le.charttime AS TIMESTAMP)) AS first_troponin_time
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  INNER JOIN qualifying_admissions qa
    ON le.hadm_id = qa.hadm_id
  WHERE LOWER(li.label) LIKE '%troponin%'
    AND le.valuenum > 0.01
    AND le.valueuom = 'ng/mL'
  GROUP BY le.hadm_id
),
troponin_values AS (
  SELECT 
    qa.hadm_id,
    MIN(le.valuenum) AS initial_troponin_t
  FROM qualifying_admissions qa
  INNER JOIN initial_troponin it
    ON qa.hadm_id = it.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON qa.hadm_id = le.hadm_id 
    AND CAST(le.charttime AS TIMESTAMP) = it.first_troponin_time
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%troponin%'
    AND le.valuenum > 0.01
    AND le.valueuom = 'ng/mL'
  GROUP BY qa.hadm_id, it.first_troponin_time
)
SELECT
  MIN(initial_troponin_t) AS min_troponin,
  PERCENTILE_CONT(initial_troponin_t, 0.25) OVER() AS p25_troponin,
  PERCENTILE_CONT(initial_troponin_t, 0.50) OVER() AS p50_troponin,
  PERCENTILE_CONT(initial_troponin_t, 0.75) OVER() AS p75_troponin,
  MAX(initial_troponin_t) AS max_troponin
FROM troponin_values;