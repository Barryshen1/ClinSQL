WITH qualifying_adms AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND (d.icd_code = 'I20.0' OR d.icd_code LIKE 'I21.%')
),
first_trop_times AS (
  SELECT q.hadm_id, MIN(l.charttime) AS first_time
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN qualifying_adms q ON l.hadm_id = q.hadm_id
  WHERE l.itemid = 50582
    AND l.valueuom = 'ng/mL'
    AND l.charttime >= q.admittime
  GROUP BY q.hadm_id
),
first_trop_values AS (
  SELECT f.hadm_id, MIN(l.valuenum) AS first_val
  FROM first_trop_times f
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON f.hadm_id = l.hadm_id 
    AND f.first_time = l.charttime
  WHERE l.itemid = 50582
    AND l.valueuom = 'ng/mL'
  GROUP BY f.hadm_id
),
filtered_values AS (
  SELECT first_val
  FROM first_trop_values
  WHERE first_val > 0.01
)
SELECT 
  PERCENTILE_CONT(first_val, 0.5) OVER() AS median,
  PERCENTILE_CONT(first_val, 0.25) OVER() AS q1,
  PERCENTILE_CONT(first_val, 0.75) OVER() AS q3,
  PERCENTILE_CONT(first_val, 0.75) OVER() - PERCENTILE_CONT(first_val, 0.25) OVER() AS iqr
FROM filtered_values
LIMIT 1;