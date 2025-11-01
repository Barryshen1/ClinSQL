WITH cohort AS (
  SELECT 
      p.subject_id, 
      p.gender,
      a.hadm_id,
      i.stay_id,
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
  WHERE 
      p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
),

temp_measurements AS (
  SELECT 
      c.subject_id,
      c.hadm_id,
      ce.charttime,
      ce.itemid,
      CASE 
          WHEN ce.itemid IN (223762, 220739) THEN ce.valuenum
          WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9 
      END AS temp_c
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON c.subject_id = ce.subject_id 
      AND c.stay_id = ce.stay_id
  WHERE 
      ce.itemid IN (223761, 223762, 220739)
      AND ce.valuenum IS NOT NULL
      AND (
          (ce.itemid IN (223762, 220739) AND ce.valuenum BETWEEN 20 AND 45) 
          OR 
          (ce.itemid = 223761 AND ce.valuenum BETWEEN 68 AND 113)
      )
),

temp_with_cat AS (
  SELECT 
      *,
      CASE 
          WHEN temp_c < 36 THEN '<36'
          WHEN temp_c < 38 THEN '36-37.9'
          ELSE '>=38'
      END AS temp_category
  FROM temp_measurements
),

mi_patients AS (
  SELECT 
      d.subject_id,
      d.hadm_id,
      1 AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR 
      (d.icd_version = 10 AND 
          (d.icd_code LIKE 'I21%' OR 
           d.icd_code LIKE 'I22%' OR 
           d.icd_code LIKE 'I23%' OR 
           d.icd_code LIKE 'I24%' OR 
           d.icd_code LIKE 'I25%'))
  GROUP BY d.subject_id, d.hadm_id
),

temp_agg AS (
  SELECT 
      temp_category,
      COUNT(*) AS measurement_count,
      COUNT(DISTINCT subject_id) AS unique_patient_count,
      AVG(temp_c) AS mean_temp,
      APPROX_QUANTILES(temp_c, 100)[OFFSET(50)] AS median_temp,
      APPROX_QUANTILES(temp_c, 100)[OFFSET(25)] AS q1_temp,
      APPROX_QUANTILES(temp_c, 100)[OFFSET(75)] AS q3_temp
  FROM temp_with_cat
  GROUP BY temp_category
),

mi_agg AS (
  SELECT 
      twc.temp_category,
      COUNT(DISTINCT twc.subject_id) AS total_patients,
      COUNT(DISTINCT IF(mi.has_mi IS NOT NULL, twc.subject_id, NULL)) AS mi_patient_count,
      SAFE_DIVIDE(
          COUNT(DISTINCT IF(mi.has_mi IS NOT NULL, twc.subject_id, NULL)), 
          COUNT(DISTINCT twc.subject_id)
      ) AS mi_rate
  FROM temp_with_cat twc
  LEFT JOIN mi_patients mi 
      ON twc.subject_id = mi.subject_id 
      AND twc.hadm_id = mi.hadm_id
  GROUP BY twc.temp_category
)

SELECT 
    ta.temp_category,
    ta.measurement_count,
    ta.unique_patient_count,
    ta.mean_temp,
    ta.median_temp,
    ta.q1_temp,
    ta.q3_temp,
    ta.q3_temp - ta.q1_temp AS iqr_temp,
    ma.mi_rate
FROM temp_agg ta
INNER JOIN mi_agg ma 
    ON ta.temp_category = ma.temp_category
ORDER BY 
    CASE ta.temp_category
        WHEN '<36' THEN 1
        WHEN '36-37.9' THEN 2
        WHEN '>=38' THEN 3
    END;