WITH acs_dx AS (
  -- diagnoses that we consider ACS based on diagnosis description (ICD-9 and ICD-10 labels)
  SELECT di.subject_id, di.hadm_id, di.seq_num, di.icd_code, d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute coronary%'
     OR LOWER(d.long_title) LIKE '%myocardial%'
     OR LOWER(d.long_title) LIKE '%unstable angina%'
),

admissions_acs AS (
  -- admissions for female patients age 50-60 that have an ACS diagnosis (primary or secondary)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group,
    CASE
      WHEN MAX(CASE WHEN acs.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      WHEN MAX(CASE WHEN acs.seq_num > 1 THEN 1 ELSE 0 END) = 1 THEN 'secondary'
      ELSE NULL
    END AS diag_position
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN acs_dx acs
    ON a.hadm_id = acs.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING
    -- require at least one ACS dx (primary or secondary)
    (MAX(CASE WHEN acs.seq_num = 1 THEN 1 ELSE 0 END) = 1
     OR MAX(CASE WHEN acs.seq_num > 1 THEN 1 ELSE 0 END) = 1)
),

proc_counts AS (
  -- count procedures per admission (treat each procedures_icd row as one procedure)
  SELECT
    ad.hadm_id,
    ad.los_group,
    ad.diag_position,
    COUNT(pi.icd_code) AS num_procedures
  FROM admissions_acs ad
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON ad.hadm_id = pi.hadm_id
  GROUP BY ad.hadm_id, ad.los_group, ad.diag_position
)

SELECT
  los_group,
  diag_position,
  q[OFFSET(1)] AS p25_procedures_per_admission,
  q[OFFSET(2)] AS p50_procedures_per_admission,
  q[OFFSET(3)] AS p75_procedures_per_admission,
  COUNT(*) AS admissions_in_stratum
FROM (
  SELECT
    los_group,
    diag_position,
    APPROX_QUANTILES(num_procedures, 4) AS q
  FROM proc_counts
  WHERE los_group IS NOT NULL
  GROUP BY los_group, diag_position
) AS quantiles
ORDER BY los_group, diag_position;