WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_counts AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(*) AS imaging_events
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    -- Filter to CT and radiography procedures using short_description
    (LOWER(d.short_description) LIKE '%ct%'
     OR LOWER(d.short_description) LIKE '%x-ray%')
  GROUP BY
    h.subject_id,
    h.hadm_id
)
SELECT
  CASE
    WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN c.los_days BETWEEN 5 AND 7 THEN '5-7'
  END AS los_group,
  COUNT(DISTINCT c.subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  ROUND(
    AVG(IFNULL(ic.imaging_events, 0)),
    2
  ) AS mean_imaging_per_admission
FROM
  cohort c
  LEFT JOIN imaging_counts ic
    ON c.subject_id = ic.subject_id
   AND c.hadm_id = ic.hadm_id
GROUP BY
  los_group
ORDER BY
  los_group;