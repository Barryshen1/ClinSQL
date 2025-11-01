WITH index_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_location LIKE '%Skilled Nursing Facility%'
    AND a.insurance = 'Medicare'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 10 AND d.icd_code IN ('J9600', 'J9601', 'J9602', 'J9620', 'J9621', 'J9622'))
      OR (d.icd_version = 9 AND d.icd_code = '51881')
    )
    AND a.hospital_expire_flag = 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

readmissions AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id AS index_hadm,
    ia.admittime AS index_admittime,
    ia.dischtime AS index_dischtime,
    ia.los_days,
    MAX(CASE WHEN ra.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ra
    ON ia.subject_id = ra.subject_id
    AND ra.admittime > ia.dischtime
    AND ra.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
  GROUP BY ia.subject_id, ia.hadm_id, ia.admittime, ia.dischtime, ia.los_days
)

SELECT
  readmitted_30d,
  COUNT(*) AS num_patients,
  PERCENTILE_CONT(los_days, 0.5) AS median_los_days,
  100.0 * SUM(CASE WHEN los_days > 8 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_gt_8
FROM readmissions
GROUP BY readmitted_30d;