WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    a.insurance,
    a.admission_location,
    d.icd_code,
    d_icd.long_title,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND d.icd_code LIKE 'I63%'  -- Ischemic stroke ICD-10 codes
),

readmissions AS (
  SELECT
    ia1.subject_id,
    ia1.hadm_id AS index_hadm_id,
    ia1.admittime AS index_admittime,
    ia1.dischtime AS index_dischtime,
    ia1.los_days AS index_los,
    ia2.hadm_id AS readmit_hadm_id,
    ia2.admittime AS readmit_admittime,
    DATE_DIFF(ia2.admittime, ia1.dischtime, DAY) AS days_to_readmit
  FROM
    index_admissions ia1
  JOIN
    index_admissions ia2
    ON ia1.subject_id = ia2.subject_id
    AND ia2.admittime > ia1.dischtime
    AND DATE_DIFF(ia2.admittime, ia1.dischtime, DAY) <= 30
),

readmission_flags AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.los_days,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_readmitted_30d
  FROM
    index_admissions ia
  LEFT JOIN
    readmissions r
    ON ia.hadm_id = r.index_hadm_id
),

final_metrics AS (
  SELECT
    COUNTIF(is_readmitted_30d = 1) * 1.0 / COUNT(*) AS readmission_rate_30d,
    PERCENTILE_CONT(CASE WHEN is_readmitted_30d = 1 THEN los_days END, 0.5) AS median_los_readmitted,
    PERCENTILE_CONT(CASE WHEN is_readmitted_30d = 0 THEN los_days END, 0.5) AS median_los_non_readmitted,
    COUNTIF(los_days > 5) * 100.0 / COUNT(*) AS pct_index_stays_gt_5_days
  FROM
    readmission_flags
)

SELECT
  readmission_rate_30d,
  median_los_readmitted,
  median_los_non_readmitted,
  pct_index_stays_gt_5_days
FROM
  final_metrics;