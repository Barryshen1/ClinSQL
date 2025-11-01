WITH first_48h_spo2 AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    AVG(ce.valuenum) AS avg_spo2
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
    AND EXTRACT(YEAR FROM icu.intime) = pat.anchor_year
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
    AND ce.itemid = 220277
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
    AND icu.los >= 2
  GROUP BY 
    icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime
  HAVING 
    avg_spo2 IS NOT NULL  -- Ensure avg exists
),
aki_cohort AS (
  SELECT 
    f48.stay_id,
    f48.subject_id,
    f48.hadm_id,
    f48.avg_spo2,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
          ON diag.icd_code = icd.icd_code 
          AND CAST(diag.icd_version AS STRING) = icd.icd_version
        WHERE 
          diag.subject_id = f48.subject_id
          AND diag.hadm_id = f48.hadm_id
          AND icd.icd_version = '10'
          AND icd.icd_code LIKE 'N17%'
      ) THEN 1 
      ELSE 0 
    END AS has_aki
  FROM 
    first_48h_spo2 f48
),
categorized_spo2 AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    has_aki,
    CASE 
      WHEN avg_spo2 < 90 THEN '<90'
      WHEN avg_spo2 >= 90 AND avg_spo2 <= 92 THEN '90-92'
      WHEN avg_spo2 >= 93 AND avg_spo2 <= 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_category
  FROM 
    aki_cohort
)
SELECT 
  spo2_category,
  COUNT(DISTINCT stay_id) AS patient_counts,
  ROUND(SUM(has_aki) * 100.0 / COUNT(DISTINCT stay_id), 2) AS aki_rate_percent
FROM 
  categorized_spo2
GROUP BY 
  spo2_category
ORDER BY 
  -- Order by numeric category for readability
  CASE spo2_category
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    ELSE 4
  END;