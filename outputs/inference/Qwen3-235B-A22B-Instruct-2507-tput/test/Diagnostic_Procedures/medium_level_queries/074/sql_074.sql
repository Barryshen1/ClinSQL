WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 1
      ELSE 0
    END AS had_icu,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_group
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_procs AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d
    ON h.hcpcs_cd = d.code
  WHERE
    LOWER(d.category) = 'imaging'
    OR LOWER(d.long_description) LIKE '%imaging%'
    OR LOWER(d.short_description) LIKE '%imaging%'
  GROUP BY
    h.hadm_id
),
admission_summary AS (
  SELECT
    pa.hadm_id,
    pa.los_group,
    pa.had_icu,
    COALESCE(ip.imaging_count, 0) AS imaging_count
  FROM
    patient_admissions pa
  LEFT JOIN
    imaging_procs ip
    ON pa.hadm_id = ip.hadm_id
  WHERE
    pa.los_group IS NOT NULL
)
SELECT
  los_group,
  had_icu,
  AVG(imaging_count) AS mean_imaging_procs,
  MIN(imaging_count) AS min_imaging_procs,
  MAX(imaging_count) AS max_imaging_procs,
  COUNT(*) AS num_admissions
FROM
  admission_summary
GROUP BY
  los_group,
  had_icu
ORDER BY
  los_group,
  had_icu;