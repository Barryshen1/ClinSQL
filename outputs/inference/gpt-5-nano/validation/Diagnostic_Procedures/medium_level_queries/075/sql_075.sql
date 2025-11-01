WITH
  -- Baseline: select male patients aged 59-69 and their admissions
  baseline AS (
    SELECT
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS days_in_hosp
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 59 AND 69
  ),

  -- Admissions with an ACS diagnosis
  acs_adm AS (
    SELECT b.hadm_id
    FROM baseline AS b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON d.hadm_id = b.hadm_id
    WHERE d.icd_code LIKE 'I21%'
       OR d.icd_code LIKE 'I22%'
       OR d.icd_code = 'I20.0'
    GROUP BY b.hadm_id
  ),

  -- Determine primary vs secondary ACS diagnosis per admission
  acs_diag_type AS (
    SELECT d.hadm_id,
           CASE WHEN MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'Primary'
                ELSE 'Secondary' END AS diag_type
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN acs_adm AS a ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE 'I21%'
       OR d.icd_code LIKE 'I22%'
       OR d.icd_code = 'I20.0'
    GROUP BY d.hadm_id
  ),

  -- Per admission diagnostic procedure count
  per_adm AS (
    SELECT a.hadm_id,
           CASE
             WHEN b.days_in_hosp BETWEEN 1 AND 3 THEN '1-3'
             WHEN b.days_in_hosp BETWEEN 4 AND 7 THEN '4-7'
             ELSE NULL
           END AS day_bucket,
           dt.diag_type,
           SUM(COALESCE(CASE WHEN ipd.long_title LIKE '%diagnostic%' THEN 1 ELSE 0 END, 0)) AS diag_procs_count
    FROM acs_adm AS a
    JOIN baseline AS b
      ON a.hadm_id = b.hadm_id
    JOIN acs_diag_type AS dt
      ON a.hadm_id = dt.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS ip
      ON a.hadm_id = ip.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS ipd
      ON ip.icd_code = ipd.icd_code
    GROUP BY a.hadm_id, day_bucket, dt.diag_type
    HAVING day_bucket IS NOT NULL
  )

SELECT
  day_bucket,
  diag_type,
  (APPROX_QUANTILES(diag_procs_count, 4)[OFFSET(1)]) AS p25,
  (APPROX_QUANTILES(diag_procs_count, 4)[OFFSET(2)]) AS p50,
  (APPROX_QUANTILES(diag_procs_count, 4)[OFFSET(3)]) AS p75
FROM per_adm
GROUP BY day_bucket, diag_type
ORDER BY day_bucket, diag_type;