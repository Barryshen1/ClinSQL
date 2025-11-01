WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    COALESCE(a.dischtime, a.admittime) AS dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 64 AND 74
),

aspirin_rx AS (
  SELECT
    p.hadm_id,
    p.starttime,
    COALESCE(p.stoptime, pa.dischtime) AS endtime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN patient_admissions pa ON p.hadm_id = pa.hadm_id
  WHERE LOWER(p.drug) LIKE '%aspirin%'
    AND p.starttime IS NOT NULL
),

p2y12_rx AS (
  SELECT
    p.hadm_id,
    p.starttime,
    COALESCE(p.stoptime, pa.dischtime) AS endtime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN patient_admissions pa ON p.hadm_id = pa.hadm_id
  WHERE (LOWER(p.drug) IN ('clopidogrel', 'prasugrel', 'ticagrelor')
     OR LOWER(p.drug) LIKE '%clopidogrel%'
     OR LOWER(p.drug) LIKE '%prasugrel%'
     OR LOWER(p.drug) LIKE '%ticagrelor%')
    AND p.starttime IS NOT NULL
),

dual_therapy AS (
  SELECT
    ar.hadm_id,
    DATETIME_DIFF(
      LEAST(ar.endtime, p2.endtime),
      GREATEST(ar.starttime, p2.starttime),
      SECOND
    ) AS overlap_seconds
  FROM aspirin_rx ar
  INNER JOIN p2y12_rx p2 ON ar.hadm_id = p2.hadm_id
  WHERE ar.starttime <= p2.endtime 
    AND p2.starttime <= ar.endtime
)

SELECT
  APPROX_QUANTILES(overlap_seconds / (24 * 60 * 60), 100)[OFFSET(50)] AS median_antiplatelet_duration_days
FROM dual_therapy
WHERE overlap_seconds > 0;