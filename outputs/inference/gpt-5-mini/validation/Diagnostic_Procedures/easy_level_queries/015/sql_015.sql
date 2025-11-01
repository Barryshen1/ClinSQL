WITH patients_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 45 AND 55
),

patient_cabg_counts AS (
  SELECT
    p.subject_id,
    -- count distinct CABG procedure occurrences per patient (distinct hadm_id|chartdate|icd_code)
    COUNT(DISTINCT CASE
      WHEN pr.icd_code IS NOT NULL
       AND (
         -- match common CABG descriptions in the procedure dictionary
         (
           LOWER(COALESCE(dp.long_title, '')) LIKE '%coronar%'
           AND LOWER(COALESCE(dp.long_title, '')) LIKE '%bypass%'
         )
         OR LOWER(COALESCE(dp.long_title, '')) LIKE '%cabg%'
       )
      THEN CONCAT(CAST(pr.hadm_id AS STRING), '|', CAST(pr.chartdate AS STRING), '|', pr.icd_code)
      ELSE NULL
    END) AS cabg_count
  FROM patients_cohort p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
   AND pr.icd_version = dp.icd_version
  GROUP BY p.subject_id
)

SELECT
  -- 25th percentile (approximate) of distinct CABG procedures per patient in the cohort
  APPROX_QUANTILES(cabg_count, 100)[OFFSET(25)] AS cabg_25th_percentile,
  COUNT(*) AS n_patients_in_cohort
FROM patient_cabg_counts;