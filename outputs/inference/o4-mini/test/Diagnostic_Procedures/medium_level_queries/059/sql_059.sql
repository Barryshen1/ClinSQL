WITH hf_adm AS (
  -- Identify admissions of 67–77 y/o men with at least one heart-failure diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE
      WHEN di_min.min_seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS primary_secondary,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN (
      -- For each admission, find the minimum seq_num among HF diagnoses
      SELECT
        di.subject_id,
        di.hadm_id,
        MIN(di.seq_num) AS min_seq_num
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON di.icd_code = dd.icd_code
         AND di.icd_version = dd.icd_version
      WHERE
        LOWER(dd.long_title) LIKE '%heart failure%'
      GROUP BY
        di.subject_id,
        di.hadm_id
    ) di_min
      ON a.subject_id = di_min.subject_id
     AND a.hadm_id    = di_min.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),
adm_imaging AS (
  -- Count HCPCS events (as proxy for imaging) per admission
  SELECT
    h.subject_id,
    h.hadm_id,
    h.primary_secondary,
    CASE
      WHEN h.los BETWEEN 1 AND 4 THEN '1-4'
      ELSE '5-7'
    END AS los_bucket,
    COUNT(hc.hcpcs_cd) AS imaging_count
  FROM
    hf_adm h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
      ON h.subject_id = hc.subject_id
     AND h.hadm_id    = hc.hadm_id
  GROUP BY
    h.subject_id,
    h.hadm_id,
    h.primary_secondary,
    los_bucket
)
-- Compute the 25th, 50th, 75th percentiles of imaging_count per group
SELECT
  primary_secondary,
  los_bucket,
  quantiles[OFFSET(1)] AS p25,
  quantiles[OFFSET(2)] AS p50,
  quantiles[OFFSET(3)] AS p75
FROM (
  SELECT
    primary_secondary,
    los_bucket,
    APPROX_QUANTILES(imaging_count, 4) AS quantiles
  FROM
    adm_imaging
  GROUP BY
    primary_secondary,
    los_bucket
)
ORDER BY
  primary_secondary,
  los_bucket;