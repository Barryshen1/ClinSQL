WITH dialysis_admissions AS (
  SELECT DISTINCT proc.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON proc.icd_code = d_proc.icd_code 
    AND proc.icd_version = d_proc.icd_version
  WHERE LOWER(d_proc.long_title) LIKE '%dialysis%'
),
filtered_admissions AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN dialysis_admissions da
    ON adm.hadm_id = da.hadm_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 44 AND 54
)
SELECT 
  STDDEV(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS sd_los_days
FROM filtered_admissions;