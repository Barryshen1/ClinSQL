WITH ecg_counts AS (
  SELECT
    adm.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_ecg_procs
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.hadm_id = proc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
    AND (
      LOWER(dproc.long_title) LIKE '%ecg%'
      OR LOWER(dproc.long_title) LIKE '%electrocardiogram%'
      OR LOWER(dproc.long_title) LIKE '%electrocardiographic%'
      OR LOWER(dproc.long_title) LIKE '%telemetry%'
    )
  GROUP BY adm.hadm_id
)
SELECT
  PERCENTILE_CONT(distinct_ecg_procs, 0.75) OVER() AS pct75_ecg_procs
FROM ecg_counts
LIMIT 1;