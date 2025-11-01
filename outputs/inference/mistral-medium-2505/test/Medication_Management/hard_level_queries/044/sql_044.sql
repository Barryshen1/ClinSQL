WITH
-- Get female patients aged 64-74 with PE diagnosis
pe_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I26.%') OR
      (d.icd_version = 9 AND d.icd_code = '415.1')
    )
),

-- Get all medications in first 24 hours of admission
first_day_meds AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN pr.drug IS NOT NULL THEN pr.drug
        WHEN ie.itemid IS NOT NULL THEN CAST(ie.itemid AS STRING)
      END
    ) AS med_count
  FROM
    pe_patients p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON
      p.hadm_id = pr.hadm_id AND
      TIMESTAMP_DIFF(pr.starttime, p.admittime, HOUR) <= 24
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` ie ON
      p.hadm_id = ie.hadm_id AND
      TIMESTAMP_DIFF(ie.starttime, p.admittime, HOUR) <= 24
  GROUP BY
    p.hadm_id
),

-- Combine with admission data and calculate tertiles
admissions_with_tertiles AS (
  SELECT
    p.hadm_id,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    f.med_count,
    NTILE(3) OVER (ORDER BY f.med_count) AS med_tertile,
    TIMESTAMP_DIFF(p.dischtime, p.admittime, DAY) AS los_days
  FROM
    pe_patients p
  JOIN
    first_day_meds f ON p.hadm_id = f.hadm_id
),

-- Calculate 30-day readmissions
readmissions AS (
  SELECT
    a1.hadm_id AS original_hadm_id,
    a1.subject_id,
    a1.dischtime,
    a2.hadm_id AS readmit_hadm_id,
    a2.admittime AS readmit_admittime,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmit
  FROM
    pe_patients a1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON
      a1.subject_id = a2.subject_id AND
      a1.hadm_id != a2.hadm_id AND
      a2.admittime > a1.dischtime AND
      TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
)

-- Final aggregation by tertile
SELECT
  med_tertile,
  COUNT(hadm_id) AS admission_count,
  MIN(med_count) AS min_med_score,
  MAX(med_count) AS max_med_score,
  ROUND(AVG(los_days), 1) AS avg_los_days,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(hadm_id), 1) AS mortality_pct,
  ROUND(100 * COUNT(DISTINCT
    CASE
      WHEN r.original_hadm_id IS NOT NULL THEN r.original_hadm_id
    END
  ) / COUNT(DISTINCT hadm_id), 1) AS readmission_30day_pct
FROM
  admissions_with_tertiles a
LEFT JOIN
  readmissions r ON a.hadm_id = r.original_hadm_id
GROUP BY
  med_tertile
ORDER BY
  med_tertile;