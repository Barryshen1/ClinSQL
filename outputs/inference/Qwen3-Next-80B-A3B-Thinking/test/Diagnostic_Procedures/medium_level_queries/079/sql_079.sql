WITH lgib_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN MAX(CASE WHEN di.seq_num = 1 AND (d.long_title LIKE '%gastrointestinal hemorrhage, lower%' OR d.long_title LIKE '%hemorrhage of rectum%') THEN 1 ELSE 0 END) = 1 THEN 'primary'
      WHEN MAX(CASE WHEN di.seq_num > 1 AND (d.long_title LIKE '%gastrointestinal hemorrhage, lower%' OR d.long_title LIKE '%hemorrhage of rectum%') THEN 1 ELSE 0 END) = 1 THEN 'secondary'
      ELSE NULL
    END AS diagnosis_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
  GROUP BY
    a.hadm_id, a.admittime, a.dischtime
  HAVING
    MAX(CASE WHEN d.long_title LIKE '%gastrointestinal hemorrhage, lower%' OR d.long_title LIKE '%hemorrhage of rectum%' THEN 1 ELSE 0 END) = 1
),
ct_procedures AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS ct_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE
    d.short_description LIKE '%CT%' OR
    d.short_description LIKE '%X-RAY%' OR
    d.short_description LIKE '%RADIOGRAPHY%' OR
    d.short_description LIKE '%RADIOGRAPH%'
  GROUP BY
    h.hadm_id
)
SELECT
  CASE
    WHEN la.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN la.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE NULL
  END AS los_group,
  la.diagnosis_type,
  AVG(COALESCE(cp.ct_count, 0)) AS mean_ct_count
FROM
  lgib_admissions la
LEFT JOIN
  ct_procedures cp ON la.hadm_id = cp.hadm_id
WHERE
  la.los_days BETWEEN 1 AND 7
GROUP BY
  los_group,
  la.diagnosis_type;