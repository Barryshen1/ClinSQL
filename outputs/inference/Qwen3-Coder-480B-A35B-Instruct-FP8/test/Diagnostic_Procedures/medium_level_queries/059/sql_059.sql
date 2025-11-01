WITH hf_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS hf_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(d.icd_code, '^I50')
),

filtered_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M' AND anchor_age BETWEEN 67 AND 77
),

imaging_counts AS (
  SELECT
    h.hadm_id,
    h.los,
    h.hf_type,
    COUNT(DISTINCT hce.hcpcs_cd) AS imaging_count
  FROM
    hf_admissions h
  JOIN
    filtered_patients p
    ON h.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.hcpcsevents hce
    ON h.hadm_id = hce.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_hcpcs dh
    ON hce.hcpcs_cd = dh.code
  WHERE
    hce.hcpcs_cd IS NOT NULL
    AND (
      LOWER(CAST(dh.long_description AS STRING)) LIKE '%imaging%'
      OR LOWER(CAST(dh.short_description AS STRING)) LIKE '%imaging%'
    )
  GROUP BY
    h.hadm_id, h.los, h.hf_type
),

los_grouped AS (
  SELECT
    imaging_count,
    hf_type,
    CASE
      WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_group
  FROM
    imaging_counts
  WHERE
    los BETWEEN 1 AND 7
)

SELECT
  los_group,
  hf_type,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS p75
FROM
  los_grouped
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group,
  hf_type
ORDER BY
  los_group,
  hf_type;