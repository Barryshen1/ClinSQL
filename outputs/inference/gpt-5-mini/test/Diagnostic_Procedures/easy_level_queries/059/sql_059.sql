WITH male_admissions AS (
  -- male patients aged 76-86 inclusive
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),

per_adm_card_counts AS (
  -- count distinct cardiac procedure ICD codes per hospitalization (hadm_id)
  SELECT
    m.hadm_id,
    COUNT(DISTINCT CASE
      WHEN d.long_title IS NOT NULL
       AND REGEXP_CONTAINS(LOWER(d.long_title),
         r'(cardiac|heart|coronary|myocard|cardio|valve|pacemaker|cabg|bypass|angioplasty|stent|percutaneous)')
      THEN proc.icd_code
      ELSE NULL
    END) AS num_card_proc
  FROM male_admissions m
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON m.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON proc.icd_code = d.icd_code
   AND proc.icd_version = d.icd_version
  GROUP BY m.hadm_id
)

-- compute 25th and 75th percentiles and IQR across hospitalizations
SELECT
  quantiles[OFFSET(1)] AS q1_25th,
  quantiles[OFFSET(3)] AS q3_75th,
  SAFE_CAST(quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS FLOAT64) AS iqr,
  (SELECT COUNT(*) FROM per_adm_card_counts) AS admissions_count
FROM (
  SELECT APPROX_QUANTILES(num_card_proc, 4) AS quantiles
  FROM per_adm_card_counts
);