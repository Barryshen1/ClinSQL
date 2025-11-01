WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location IN ('EMERGENCY ROOM ADMIT', 'EMERGENCY ROOM')
    AND (
      (d.icd_version = '9' AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '436%'))
      OR (d.icd_version = '10' AND d.icd_code LIKE 'I63%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
),
readmission_flag AS (
  SELECT
    c.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` r
      WHERE r.subject_id = c.subject_id
        AND r.admittime > c.dischtime
        AND r.admittime <= DATE_ADD(c.dischtime, INTERVAL 30 DAY)
        AND r.hadm_id != c.hadm_id
    ) THEN 1 ELSE 0 END AS readmitted
  FROM cohort c
)
SELECT
  AVG(r.readmitted) * 100 AS readmission_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN r.readmitted = 1 THEN los ELSE NULL END) AS median_los_readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN r.readmitted = 0 THEN los ELSE NULL END) AS median_los_non_readmitted,
  AVG(CASE WHEN los > 5 THEN 1 ELSE 0 END) * 100 AS percent_stays_gt_5_days
FROM cohort c
JOIN readmission_flag r ON c.hadm_id = r.hadm_id;