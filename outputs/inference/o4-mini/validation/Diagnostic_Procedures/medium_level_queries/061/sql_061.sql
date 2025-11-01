WITH aki_admissions AS (
  -- Step 1 & 2: Filter female patients age 64-74 with AKI, classify AKI as primary vs secondary
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE
      WHEN MAX(
        CASE 
          WHEN LOWER(diag.long_title) LIKE '%acute kidney injury%'
           AND d.seq_num = 1
          THEN 1 ELSE 0
        END
      ) = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS aki_diag_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON adm.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
      ON d.icd_code = diag.icd_code
     AND d.icd_version = diag.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND LOWER(diag.long_title) LIKE '%acute kidney injury%'
    AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
  GROUP BY
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
),
imaging_counts AS (
  -- Step 4: Count radiology procedure events per admission
  SELECT
    a.hadm_id,
    COUNT(*) AS imaging_count
  FROM
    aki_admissions a
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON a.hadm_id = pe.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` items
      ON pe.itemid = items.itemid
  WHERE
    items.category = 'Radiology'
    AND pe.starttime BETWEEN a.admittime AND a.dischtime
  GROUP BY
    a.hadm_id
),
admission_summary AS (
  -- Combine LOS bucket, diagnosis type, and imaging counts
  SELECT
    a.hadm_id,
    a.aki_diag_type,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      ELSE '4-7 days'
    END AS los_bucket,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM
    aki_admissions a
    LEFT JOIN imaging_counts ic
      ON a.hadm_id = ic.hadm_id
)
-- Step 5: Compute median and IQR per group
SELECT
  los_bucket,
  aki_diag_type,
  QUANTILES[OFFSET(50)]   AS median_imaging,
  QUANTILES[OFFSET(25)]   AS imaging_q1,
  QUANTILES[OFFSET(75)]   AS imaging_q3
FROM (
  SELECT
    los_bucket,
    aki_diag_type,
    APPROX_QUANTILES(imaging_count, 100) AS QUANTILES
  FROM
    admission_summary
  GROUP BY
    los_bucket,
    aki_diag_type
)
ORDER BY
  los_bucket,
  aki_diag_type;