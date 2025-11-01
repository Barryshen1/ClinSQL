WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.insurance,
    a.admission_location,
    p.gender,
    p.anchor_age,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND LOWER(a.admission_location) LIKE '%transfer from another hosp%'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '410')
      OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I21')
    )
    AND (a.hospital_expire_flag = 0 OR a.deathtime IS NULL)
),

index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM cohort
),

readmissions AS (
  -- For each index admission, find if a subsequent admission within 30 days exists
  SELECT
    ia.subject_id,
    ia.hadm_id,
    MIN(a2.admittime) AS next_admit_time
  FROM index_admissions ia
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON ia.subject_id = a2.subject_id
    AND a2.admittime > ia.dischtime
    AND DATETIME_DIFF(a2.admittime, ia.dischtime, DAY) <= 30
  GROUP BY ia.subject_id, ia.hadm_id
),

final AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.los,
    CASE WHEN r.next_admit_time IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM index_admissions ia
  LEFT JOIN readmissions r
    ON ia.subject_id = r.subject_id AND ia.hadm_id = r.hadm_id
)

SELECT
  CASE WHEN readmitted_30d = 1 THEN 'Readmitted within 30d' ELSE 'Not readmitted within 30d' END AS group_label,
  COUNT(*) AS n_index_admissions,
  ROUND(COUNTIF(readmitted_30d = 1) / COUNT(*) * 100, 2) AS readmission_rate_percent,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_days,
  ROUND(COUNTIF(los > 4) / COUNT(*) * 100, 2) AS percent_los_gt_4_days
FROM final
GROUP BY group_label
ORDER BY group_label DESC;