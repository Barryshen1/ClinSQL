WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.insurance,
    adm.admission_location,
    pat.gender,
    pat.anchor_age,
    diag.icd_code,
    diag.icd_version,
    diag.seq_num,
    icd.long_title,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND adm.insurance LIKE '%Medicare%'
    AND adm.admission_location LIKE '%SNF%'
    AND diag.seq_num = 1
    AND LOWER(icd.long_title) LIKE '%urinary tract infection%'
    AND adm.hospital_expire_flag = 0
),

readmissions AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.dischtime,
    MIN(a2.admittime) AS next_admit_time,
    COUNT(a2.hadm_id) AS num_readmits
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON c.subject_id = a2.subject_id
    AND a2.admittime > c.dischtime
    AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY
    c.subject_id, c.hadm_id, c.dischtime
),

final AS (
  SELECT
    c.*,
    CASE WHEN r.num_readmits > 0 THEN 1 ELSE 0 END AS readmitted
  FROM
    cohort c
  LEFT JOIN
    readmissions r
    ON c.subject_id = r.subject_id AND c.hadm_id = r.hadm_id
),

median_los AS (
  SELECT
    readmitted,
    PERCENTILE_CONT(los, 0.5) OVER (PARTITION BY readmitted) AS median_los
  FROM
    final
)

SELECT
  f.readmitted,
  COUNT(*) AS num_index_admissions,
  ROUND(SUM(f.readmitted) / COUNT(*) * 100, 2) AS readmission_rate_percent,
  ROUND(m.median_los, 1) AS median_los,
  ROUND(SUM(CASE WHEN f.los > 6 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS percent_los_gt_6_days
FROM
  final f
LEFT JOIN
  (
    SELECT DISTINCT readmitted, median_los FROM median_los
  ) m
  ON f.readmitted = m.readmitted
GROUP BY
  f.readmitted, m.median_los
ORDER BY
  f.readmitted DESC;