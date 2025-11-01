WITH female_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),

cabg_events AS (
  -- Identify CABG-related procedure records by matching the procedure description
  SELECT pr.subject_id,
         pr.hadm_id,
         pr.chartdate,
         pr.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
   AND pr.icd_version = dp.icd_version
  WHERE LOWER(COALESCE(dp.long_title, '')) LIKE '%bypass%'
    AND (
      LOWER(COALESCE(dp.long_title, '')) LIKE '%coronary%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%cabg%'
    )
),

per_patient_cabg_counts AS (
  -- Count distinct CABG procedure occurrences per patient.
  -- Define an occurrence by (hadm_id, chartdate, icd_code) to deduplicate repeated rows.
  SELECT f.subject_id,
         COALESCE(
           COUNT(DISTINCT CONCAT(CAST(c.hadm_id AS STRING), '||', CAST(COALESCE(CAST(c.chartdate AS STRING), '') AS STRING), '||', c.icd_code)),
           0
         ) AS cabg_count
  FROM female_cohort f
  LEFT JOIN cabg_events c
    ON f.subject_id = c.subject_id
  GROUP BY f.subject_id
)

SELECT
  COUNT(*) AS num_females_41_51,
  STDDEV_POP(cabg_count) AS sd_cabg_per_patient_population
FROM per_patient_cabg_counts;