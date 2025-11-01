WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    d.icd_code,
    d.long_title,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE
          a2.subject_id = a.subject_id
          AND a2.hadm_id != a.hadm_id
          AND a2.admittime > a.dischtime
          AND a2.admittime <= DATE_ADD(a.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND diag.seq_num = 1
    AND LOWER(d.long_title) LIKE '%urinary tract infection%'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    AND a.dischtime IS NOT NULL
)

SELECT
  AVG(readmitted) * 100 AS readmission_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN readmitted = 1 THEN los END) AS median_los_readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN readmitted = 0 THEN los END) AS median_los_non_readmitted,
  (SUM(CASE WHEN los > 6 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percent_stays_gt_6_days
FROM
  index_admissions;