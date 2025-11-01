WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),
-- Pre-filter the HCPCS codes for x-ray or CT
imaging_codes AS (
  SELECT
    code
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE
    LOWER(short_description) LIKE '%x-ray%'
    OR LOWER(short_description) LIKE '%ct%'
),
-- Count imaging events only for our eligible admissions and the filtered codes
imaging_events AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
  JOIN
    imaging_codes AS ic
    ON h.hcpcs_cd = ic.code
  JOIN
    eligible_admissions AS ea
    ON h.hadm_id = ea.hadm_id
  GROUP BY
    h.hadm_id
),
-- Filter AMI diagnoses to our eligible admissions and classify primary vs secondary
ami_flags AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary,
    MAX(CASE WHEN di.seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  JOIN
    eligible_admissions AS ea
    ON di.hadm_id = ea.hadm_id
  WHERE
    LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
  GROUP BY
    di.hadm_id
),
analysis_ready AS (
  SELECT
    ea.hadm_id,
    CASE
      WHEN ea.stay_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN ea.stay_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS stay_group,
    CASE
      WHEN af.is_primary = 1 THEN 'primary'
      WHEN af.is_primary = 0 AND af.has_secondary = 1 THEN 'secondary'
      ELSE NULL
    END AS ami_type,
    COALESCE(ie.imaging_count, 0) AS cnt
  FROM
    eligible_admissions AS ea
  JOIN
    ami_flags AS af
    ON ea.hadm_id = af.hadm_id
  LEFT JOIN
    imaging_events AS ie
    ON ea.hadm_id = ie.hadm_id
  WHERE
    ea.stay_days BETWEEN 1 AND 7
),
-- Final aggregation: compute the five-number summary (0th, 25th, 50th, 75th, 100th percentiles)
results AS (
  SELECT
    stay_group,
    ami_type,
    APPROX_QUANTILES(cnt, 4) AS quantiles_array
  FROM
    analysis_ready
  GROUP BY
    stay_group,
    ami_type
)
SELECT
  stay_group,
  ami_type,
  quantiles_array[OFFSET(1)] AS p25,
  quantiles_array[OFFSET(2)] AS p50,
  quantiles_array[OFFSET(3)] AS p75
FROM
  results
ORDER BY
  stay_group,
  ami_type;