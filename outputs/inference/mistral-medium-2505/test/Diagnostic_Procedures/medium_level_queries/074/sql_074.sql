WITH female_40_50_admissions AS (
  -- Filter for female patients aged 40-50 with 1-7 day hospital stays
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

icu_stays AS (
  -- Get ICU stay durations for these admissions
  SELECT
    f.subject_id,
    f.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    DATETIME_DIFF(i.outtime, i.intime, DAY) AS icu_stay_days,
    CASE
      WHEN DATETIME_DIFF(i.outtime, i.intime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATETIME_DIFF(i.outtime, i.intime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS icu_stay_duration_group
  FROM
    female_40_50_admissions f
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    f.subject_id = i.subject_id AND f.hadm_id = i.hadm_id
  WHERE
    DATETIME_DIFF(i.outtime, i.intime, DAY) BETWEEN 1 AND 7
),

imaging_procedures AS (
  -- Count imaging procedures per admission
  SELECT
    i.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_procedure_count
  FROM
    icu_stays i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  ON
    i.hadm_id = h.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON
    h.hcpcs_cd = d.code
  WHERE
    -- Filter for imaging procedures (adjust as needed)
    (d.short_description LIKE '%CT%'
     OR d.short_description LIKE '%MRI%'
     OR d.short_description LIKE '%XRAY%'
     OR d.short_description LIKE '%ULTRASOUND%'
     OR d.short_description LIKE '%IMAGING%')
  GROUP BY
    i.hadm_id
)

-- Final aggregation by ICU stay duration group
SELECT
  icu_stay_duration_group,
  COUNT(DISTINCT i.hadm_id) AS admission_count,
  AVG(ip.imaging_procedure_count) AS mean_imaging_procedures,
  MIN(ip.imaging_procedure_count) AS min_imaging_procedures,
  MAX(ip.imaging_procedure_count) AS max_imaging_procedures
FROM
  icu_stays i
LEFT JOIN
  imaging_procedures ip
ON
  i.hadm_id = ip.hadm_id
WHERE
  icu_stay_duration_group IS NOT NULL
GROUP BY
  icu_stay_duration_group
ORDER BY
  icu_stay_duration_group;