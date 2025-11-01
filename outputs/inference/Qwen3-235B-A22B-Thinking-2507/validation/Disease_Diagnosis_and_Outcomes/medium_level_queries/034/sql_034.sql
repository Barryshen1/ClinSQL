WITH base AS (
  SELECT 
    adm.hadm_id,
    adm.hospital_expire_flag,
    -- Compute LOS in days (fractional)
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24*3600.0) AS los_days,
    -- For non-survivors, compute time_to_death in days (fractional)
    CASE WHEN adm.hospital_expire_flag = 1 
         THEN TIMESTAMP_DIFF(adm.deathtime, adm.admittime, SECOND) / (24*3600.0)
         ELSE NULL 
    END AS time_to_death_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  -- Join to get primary diagnosis (seq_num=1) and check if it's heart failure
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND diag.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 70 AND 80
    AND LOWER(d_diag.long_title) LIKE '%heart failure%'
)
SELECT
  CASE WHEN los_days < 8 THEN 'LOS<8' ELSE 'LOS>=8' END AS los_group,
  COUNT(*) AS admission_count,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag=1 THEN time_to_death_days END, 100)[OFFSET(50)] AS median_time_to_death_days
FROM base
GROUP BY los_group
ORDER BY los_group;