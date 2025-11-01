WITH acs_dx AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(IF(LOWER(d.long_title) LIKE '%acute coronary syndrome%', 1, 0)) AS has_any,
    MAX(IF(LOWER(d.long_title) LIKE '%acute coronary syndrome%' AND di.seq_num = 1, 1, 0)) AS has_primary
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute coronary syndrome%'
  GROUP BY di.subject_id, di.hadm_id
),

us_counts AS (
  SELECT
    hc.subject_id,
    hc.hadm_id,
    COUNT(*) AS us_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON hc.hcpcs_cd = d.code
  WHERE LOWER(d.long_description) LIKE '%ultrasound%'
  GROUP BY hc.subject_id, hc.hadm_id
)

SELECT
  ea.los_group,
  ea.diag_group,
  ROUND(AVG(ea.us_count), 2) AS mean_ultrasounds,
  MIN(ea.us_count)         AS min_ultrasounds,
  MAX(ea.us_count)         AS max_ultrasounds
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group,
    CASE
      WHEN acs.has_primary = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diag_group,
    COALESCE(u.us_count, 0) AS us_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN acs_dx acs
    ON a.subject_id = acs.subject_id
   AND a.hadm_id    = acs.hadm_id
  LEFT JOIN us_counts u
    ON a.subject_id = u.subject_id
   AND a.hadm_id    = u.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 89
    AND p.anchor_year_group <> '>= 90'
    AND acs.has_any = 1
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
) ea
GROUP BY ea.los_group, ea.diag_group
ORDER BY ea.los_group, ea.diag_group;