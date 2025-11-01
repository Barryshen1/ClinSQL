WITH
-- identify admissions with acute pancreatitis and whether it's primary (seq_num=1) or secondary (seq_num>1)
diag_pancreatitis AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(dic.long_title) LIKE '%acute pancreatitis%' AND d.seq_num = 1 THEN 1 ELSE 0 END) AS has_primary,
    MAX(CASE WHEN LOWER(dic.long_title) LIKE '%acute pancreatitis%' AND d.seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
      ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
  WHERE
    LOWER(dic.long_title) LIKE '%acute pancreatitis%'
  GROUP BY
    d.hadm_id
),

-- count imaging-like HCPCS/CPT events per hadm_id in the HOSP module
imaging_hcpcs AS (
  SELECT
    h.hadm_id,
    COUNT(1) AS hcpcs_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    h.hadm_id IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(CONCAT(IFNULL(h.short_description,''), ' ', IFNULL(d.long_description,''))),
      'ct|x-?ray|radiograph|computed tomography|chest x-?ray|head ct|abdomen ct')
  GROUP BY
    h.hadm_id
),

-- count imaging-like procedureevents per hadm_id in the ICU module (join to d_items)
imaging_procevents AS (
  SELECT
    p.hadm_id,
    COUNT(1) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON p.itemid = di.itemid
  WHERE
    p.hadm_id IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(di.label, '')),
      'ct|x-?ray|radiograph|computed tomography|chest x-?ray|head ct|abdomen ct')
  GROUP BY
    p.hadm_id
),

-- start from admissions, restrict to males age 51-61 and admissions that have pancreatitis (primary or secondary),
-- compute LOS and join imaging counts
admissions_with_counts AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- LOS in whole days (integer)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- classify LOS bin
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group,
    -- determine diagnosis type: prefer primary if present, else secondary
    CASE
      WHEN dp.has_primary = 1 THEN 'primary'
      WHEN dp.has_primary = 0 AND dp.has_secondary = 1 THEN 'secondary'
      ELSE NULL
    END AS diag_type,
    COALESCE(hc.hcpcs_count, 0) + COALESCE(pr.proc_count, 0) AS total_imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON a.subject_id = pat.subject_id
    JOIN diag_pancreatitis dp
      ON a.hadm_id = dp.hadm_id
    LEFT JOIN imaging_hcpcs hc
      ON a.hadm_id = hc.hadm_id
    LEFT JOIN imaging_procevents pr
      ON a.hadm_id = pr.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
    -- only keep admissions where we can classify as primary or secondary and LOS in 1-7 days
    AND ( (dp.has_primary = 1) OR (dp.has_secondary = 1) )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
)

-- final aggregation: per LOS bin and diagnosis type
SELECT
  los_group AS los_bin,
  diag_type AS pancreatitis_diagnosis_type,
  COUNT(DISTINCT subject_id) AS distinct_patient_count,
  COUNT(1) AS admission_count,
  ROUND(AVG(total_imaging_count), 3) AS mean_imaging_per_admission
FROM
  admissions_with_counts
WHERE
  los_group IS NOT NULL
  AND diag_type IS NOT NULL
GROUP BY
  los_group,
  diag_type
ORDER BY
  los_group,
  diag_type;