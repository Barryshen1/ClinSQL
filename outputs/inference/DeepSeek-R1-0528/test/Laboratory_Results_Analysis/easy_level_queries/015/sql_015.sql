WITH cohort AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code 
    AND diag.icd_version = d.icd_version
  WHERE 
    pat.gender = 'F'
    AND d.long_title LIKE '%pneumonia%'
),
creatinine_data AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    l.charttime,
    UNIX_SECONDS(CAST(l.charttime AS TIMESTAMP)) AS charttime_sec,  -- Convert to numeric seconds
    CASE 
      WHEN l.valueuom = 'mg/dL' THEN l.valuenum
      WHEN l.valueuom = 'umol/L' THEN l.valuenum / 88.4
    END AS creatinine_mgdL
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort
    ON l.hadm_id = cohort.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON l.itemid = dlab.itemid
  WHERE 
    dlab.label = 'Creatinine'
    AND dlab.fluid = 'Blood'
    AND l.valuenum IS NOT NULL
    AND l.valueuom IN ('mg/dL', 'umol/L')
),
rolling_avg AS (
  SELECT 
    subject_id,
    hadm_id,
    charttime,
    AVG(creatinine_mgdL) OVER (
      PARTITION BY subject_id, hadm_id
      ORDER BY charttime_sec  -- Order by numeric seconds
      RANGE BETWEEN 86400 PRECEDING AND CURRENT ROW  -- 24 hours in seconds
    ) AS avg_24h_creatinine
  FROM creatinine_data
)
SELECT 
  MIN(avg_24h_creatinine) AS min_24h_avg_creatinine
FROM rolling_avg;