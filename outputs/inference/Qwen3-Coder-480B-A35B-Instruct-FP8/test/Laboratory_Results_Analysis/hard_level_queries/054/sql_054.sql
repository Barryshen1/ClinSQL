WITH ami_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    a.hospital_expire_flag,
    p.anchor_age,
    COUNT(l.labevent_id) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'abnormal'
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND dd.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND dd.icd_code LIKE 'I21%')
    )
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM
    ami_cohort
),

quartile_summary AS (
  SELECT
    quartile,
    COUNT(*) AS patient_count,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    quartiles
  GROUP BY
    quartile
),

control_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.hadm_id NOT IN (
      SELECT DISTINCT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE (
        (d.icd_version = 9 AND d.icd_code LIKE '410%')
        OR
        (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
      )
    )
),

control_abnormal_labs AS (
  SELECT
    COUNT(l.labevent_id) AS total_abnormal_labs
  FROM
    control_cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'abnormal'
)

SELECT
  q.quartile,
  q.patient_count,
  q.avg_los,
  q.mortality_rate,
  ctl.total_abnormal_labs AS control_abnormal_lab_count
FROM
  quartile_summary q
CROSS JOIN
  control_abnormal_labs ctl
ORDER BY
  q.quartile;