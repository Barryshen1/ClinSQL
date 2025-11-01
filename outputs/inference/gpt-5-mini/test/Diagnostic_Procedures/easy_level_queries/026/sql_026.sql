WITH cohort AS (
  -- Men aged 75-85 inclusive
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE (gender = 'M' OR LOWER(gender) LIKE 'male%')
    AND anchor_age BETWEEN 75 AND 85
),

proc_of_interest AS (
  -- Procedures whose description mentions ablation or cardioversion (ICD-9/ICD-10 via d_icd_procedures)
  SELECT DISTINCT
    pr.subject_id,
    COALESCE(CAST(pr.hadm_id AS STRING), 'nohadm') AS hadm_id_str,
    CAST(pr.chartdate AS STRING) AS chartdate_str,
    pr.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code AND pr.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ablat%'   -- captures "ablation", "ablative", etc.
     OR LOWER(d.long_title) LIKE '%cardioversion%'
),

events_per_patient AS (
  -- Count distinct procedure events per patient (unique by hadm_id + chartdate + icd_code)
  SELECT
    subject_id,
    COUNT(1) AS proc_count
  FROM (
    SELECT
      subject_id,
      -- create an event key to deduplicate same-code same-date same-admission occurrences
      CONCAT(hadm_id_str, '|' , COALESCE(chartdate_str, ''), '|' , COALESCE(icd_code, '')) AS event_key
    FROM proc_of_interest
    GROUP BY subject_id, CONCAT(hadm_id_str, '|' , COALESCE(chartdate_str, ''), '|' , COALESCE(icd_code, ''))
  )
  GROUP BY subject_id
),

per_patient AS (
  -- Include all cohort members, assigning zero where no events found
  SELECT
    c.subject_id,
    COALESCE(e.proc_count, 0) AS proc_count
  FROM cohort c
  LEFT JOIN events_per_patient e
    ON c.subject_id = e.subject_id
)

-- Compute 25th and 75th percentiles and IQR using APPROX_QUANTILES
SELECT
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(75)] AS p75,
  SAFE_CAST(quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS INT64) AS iqr,
  (SELECT COUNT(*) FROM per_patient) AS total_patients
FROM (
  SELECT APPROX_QUANTILES(proc_count, 100) AS quantiles
  FROM per_patient
);