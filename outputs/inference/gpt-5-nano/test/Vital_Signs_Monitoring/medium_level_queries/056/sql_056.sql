WITH cohort AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 89 AND 99
),

temps AS (
  SELECT c.subject_id, c.hadm_id, c.stay_id, ce.charttime, ce.valuenum
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON ic.subject_id = c.subject_id
   AND ic.hadm_id = c.hadm_id
   AND ic.stay_id = c.stay_id
  WHERE (LOWER(di.label) LIKE '%temperature%' OR LOWER(di.label) LIKE '%temp%')
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ic.intime AND ic.outtime
),

temp_with_cat AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    valuenum,
    CASE
      WHEN valuenum < 36 THEN '<36'
      WHEN valuenum >= 36 AND valuenum < 38 THEN '36-37.9'
      WHEN valuenum >= 38 THEN '>=38'
      ELSE NULL
    END AS temp_cat
  FROM temps
  WHERE valuenum IS NOT NULL
    AND (valuenum < 36 OR (valuenum >= 36 AND valuenum < 38) OR (valuenum >= 38))
),

t_for_quant AS (
  SELECT temp_cat, subject_id, valuenum
  FROM temp_with_cat
  WHERE temp_cat IS NOT NULL
),

quant AS (
  -- per category, compute quantiles for valuenum
  SELECT temp_cat, APPROX_QUANTILES(valuenum, 100) AS q_arr
  FROM t_for_quant
  GROUP BY temp_cat
),

quant_vals AS (
  SELECT temp_cat,
         q_arr[OFFSET(50)] AS median_temp,
         q_arr[OFFSET(25)] AS q1,
         q_arr[OFFSET(75)] AS q3
  FROM quant
),

cat_agg AS (
  SELECT t.temp_cat,
         AVG(t.valuenum) AS mean_temp,
         qv.median_temp,
         qv.q1,
         qv.q3,
         (qv.q3 - qv.q1) AS iqr,
         COUNT(DISTINCT t.subject_id) AS unique_patients,
         COUNT(*) AS measurement_count
  FROM t_for_quant t
  JOIN quant_vals qv ON t.temp_cat = qv.temp_cat
  GROUP BY t.temp_cat, qv.median_temp, qv.q1, qv.q3
),

mi_by_subject AS (
  -- MI indicator per subject across their admissions in the cohort
  SELECT c.subject_id,
         MAX(CASE
               WHEN (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '412%'))
                    OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
               THEN 1 ELSE 0
             END) AS mi_present
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  GROUP BY c.subject_id
),

mi_rate AS (
  -- MI rate per temperature category: among subjects who contributed readings in the category
  SELECT t.temp_cat,
         COUNT(DISTINCT t.subject_id) AS unique_patients_in_cat,
         SUM(CASE WHEN m.mi_present = 1 THEN 1 ELSE 0 END) AS mi_counts
  FROM (
     SELECT DISTINCT subject_id, temp_cat
     FROM temp_with_cat
  ) t
  LEFT JOIN mi_by_subject m ON t.subject_id = m.subject_id
  GROUP BY t.temp_cat
)

SELECT
  ca.temp_cat,
  ca.mean_temp,
  ca.median_temp,
  ca.q1,
  ca.q3,
  ca.iqr,
  ca.unique_patients,
  ca.measurement_count,
  SAFE_DIVIDE(mr.mi_counts, ca.unique_patients) AS mi_rate
FROM cat_agg ca
LEFT JOIN mi_rate mr ON ca.temp_cat = mr.temp_cat
ORDER BY ca.temp_cat;