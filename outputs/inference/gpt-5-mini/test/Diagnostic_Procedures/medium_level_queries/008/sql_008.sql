WITH male_adm AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING(subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.dischtime IS NOT NULL
    -- limit to LOS 1-7 for the two groups of interest
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),

-- For each admission count radiography/CT HCPCS events that occur during the admission
adm_imaging AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.los,
    -- count HCPCS rows on this admission that match imaging patterns
    COUNTIF(
      REGEXP_CONTAINS(
        LOWER(CONCAT(COALESCE(h.short_description, ''), ' ', COALESCE(d.long_description, ''))),
        r'computed tomograph|computed tomography|ct scan|x-?ray|radiograph|radiography|cat scan|xray'
      )
    ) AS imaging_count
  FROM male_adm m
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON m.hadm_id = h.hadm_id
    AND h.chartdate BETWEEN DATE(m.admittime) AND DATE(m.dischtime)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  GROUP BY m.subject_id, m.hadm_id, m.los
)

SELECT
  CASE
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'other'
  END AS los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  ROUND(AVG(imaging_count), 3) AS mean_radiography_ct_per_admission
FROM adm_imaging
GROUP BY los_group
HAVING los_group IN ('1-4 days', '5-7 days')
ORDER BY los_group;