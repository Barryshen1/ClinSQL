WITH femoral_index AS (
  -- Identify index admissions that meet inclusion criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- LOS in days (integer days)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.hadm_id = di.hadm_id AND di.seq_num = 1  -- principal diagnosis
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND a.admission_type = 'EMERGENCY'
    AND a.hospital_expire_flag = 0  -- exclude in-hospital deaths (cannot be readmitted)
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- Match likely femoral neck fracture ICDs / descriptions (ICD-9 820*, ICD-10 S72.0*, or descriptive text)
    AND (
      LOWER(COALESCE(dd.long_title, '')) LIKE '%femoral neck%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%neck of femur%'
      OR di.icd_code LIKE '820%'       -- ICD-9 fracture of neck of femur
      OR LOWER(di.icd_code) LIKE 's72.0%'  -- ICD-10 fracture of neck of femur (S72.0*)
    )
),

index_with_readmit AS (
  -- For each index admission determine whether there is any readmission within 30 days
  SELECT
    fi.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = fi.subject_id
        AND a2.hadm_id != fi.hadm_id
        AND a2.admittime IS NOT NULL
        AND a2.admittime > fi.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(fi.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_within_30d
  FROM femoral_index fi
)

SELECT
  COUNT(*) AS total_index_admissions,
  -- readmission rate (%)
  ROUND( 100.0 * SUM(CASE WHEN readmitted_within_30d THEN 1 ELSE 0 END) / COUNT(*), 2) AS readmission_rate_pct,
  -- median LOS for readmitted (approximate median using APPROX_QUANTILES)
  CAST(
    (SELECT IFNULL(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 0)
     FROM index_with_readmit
     WHERE readmitted_within_30d = TRUE)
    AS INT64
  ) AS median_los_readmitted_days,
  -- median LOS for non-readmitted
  CAST(
    (SELECT IFNULL(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 0)
     FROM index_with_readmit
     WHERE readmitted_within_30d = FALSE)
    AS INT64
  ) AS median_los_non_readmitted_days,
  -- percent of initial stays > 8 days
  ROUND( 100.0 * SUM(CASE WHEN los_days > 8 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_index_stays_gt_8_days
FROM index_with_readmit;