WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    MAX(CASE WHEN t.careunit LIKE '%ICU%' THEN 1 ELSE 0 END) AS icu_used
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON a.hadm_id = t.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(did.long_title) LIKE '%heart failure%'
  GROUP BY
    a.hadm_id, a.subject_id, los_days
  HAVING
    los_days BETWEEN 1 AND 8
),

radiology_counts AS (
  SELECT
    a.hadm_id,
    COUNT(h.hcpcs_cd) AS radiology_count
  FROM
    admissions_filtered a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON a.hadm_id = h.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE
    h.chartdate IS NOT NULL
    AND (
      LOWER(dh.short_description) LIKE '%ct%'
      OR LOWER(dh.short_description) LIKE '%radiograph%'
    )
  GROUP BY
    a.hadm_id
),

admissions_with_radiology AS (
  SELECT
    a.*,
    COALESCE(r.radiology_count, 0) AS radiology_count,
    CASE
      WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN a.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM
    admissions_filtered a
  LEFT JOIN
    radiology_counts r
    ON a.hadm_id = r.hadm_id
)

SELECT
  los_group,
  icu_used,
  APPROX_QUANTILES(radiology_count, 4)[OFFSET(1)] AS percentile_25,
  APPROX_QUANTILES(radiology_count, 4)[OFFSET(2)] AS percentile_50,
  APPROX_QUANTILES(radiology_count, 4)[OFFSET(3)] AS percentile_75
FROM
  admissions_with_radiology
GROUP BY
  los_group, icu_used
ORDER BY
  los_group, icu_used;