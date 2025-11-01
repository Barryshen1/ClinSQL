SELECT 
    le.subject_id, le.hadm_id,
    COUNT(DISTINCT le.itemid) AS lab_count
  FROM target_cohort tc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON CAST(tc.subject_id AS STRING) = le.subject_id 
    AND CAST(tc.hadm_id AS STRING) = le.hadm_id
    AND le.charttime >= tc.intime
    AND le.charttime < TIMESTAMP_ADD(tc.intime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
  GROUP BY le.subject_id, le.hadm_id
) lab ON ...;